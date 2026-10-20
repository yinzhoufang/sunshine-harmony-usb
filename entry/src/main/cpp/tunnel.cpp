#include "tunnel.h"
#include <algorithm>
#include <arpa/inet.h>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <netinet/tcp.h>
#include <unistd.h>
#include <hilog/log.h>

namespace {
constexpr size_t QUEUE_LIMIT = 2 * 1024 * 1024;
constexpr int BATCH = 64; // fairness budget; never a downlink drop threshold
uint64_t NowUs() {
    return std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}
sockaddr_in Address(const std::string &host, int port) {
    sockaddr_in a{};
    a.sin_family = AF_INET;
    a.sin_port = htons(static_cast<uint16_t>(port));
    inet_pton(AF_INET, host.c_str(), &a.sin_addr);
    return a;
}
bool Nonblock(int fd) { return fcntl(fd, F_SETFL, O_NONBLOCK) == 0; }
void Close(int &fd) { if (fd >= 0) close(fd); fd = -1; }
bool Again() { return errno == EAGAIN || errno == EWOULDBLOCK; }
void Log(const char *event, int lane, int error = 0) {
    OH_LOG_Print(LOG_APP, LOG_INFO, 0x0001, "UsbTunnel",
        "native %{public}s lane=%{public}d errno=%{public}d", event, lane, error);
}
}

int Tunnel::Start(const Config &cfg) {
    Stop();
    cfg_ = cfg;
    stats_ = {};
    dispatchHistogram_.fill(0);
    for (int ch = 0; ch < 3; ++ch) {
        clients_[ch] = Address("127.0.0.1", cfg.clientPorts[ch]);
        clientSocket_[ch] = 3 + ch;
    }
    for (int i = 0; i < 6; ++i) {
        int fd = socket(AF_INET, SOCK_DGRAM, 0);
        udp_[i] = fd;
        if (fd < 0) { int e = errno; Cleanup(); return e; }
        int buf = 8 * 1024 * 1024;
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &buf, sizeof(buf));
        setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &buf, sizeof(buf));
        auto addr = Address(i < 3 ? cfg.listenHost : "127.0.0.1", cfg.serverPorts[i % 3]);
        if (!Nonblock(fd) || bind(fd, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) != 0) {
            int e = errno; Cleanup(); return e;
        }
    }
    if (pipe(wake_) != 0) { int e = errno; Cleanup(); return e; }
    Nonblock(wake_[0]); Nonblock(wake_[1]);
    running_ = true;
    worker_ = std::thread(&Tunnel::Run, this);
    return 0;
}

void Tunnel::Stop() {
    running_ = false;
    if (wake_[1] >= 0) { const char b = 1; (void)write(wake_[1], &b, 1); }
    if (worker_.joinable()) worker_.join();
    Cleanup();
}

void Tunnel::Cleanup() {
    for (auto &fd : udp_) Close(fd);
    for (auto &lane : lanes_) { Close(lane.fd); lane = Lane{}; }
    Close(wake_[0]); Close(wake_[1]);
}

Snapshot Tunnel::Stats() {
    std::lock_guard<std::mutex> lock(statsMutex_);
    Snapshot s = stats_;
    uint64_t total = 0, count = 0;
    for (auto n : dispatchHistogram_) total += n;
    for (size_t i = 0; total && i < dispatchHistogram_.size(); ++i) {
        count += dispatchHistogram_[i];
        if (count * 100 >= total * 99) { s.dispatchP99Us = 1ULL << i; break; }
    }
    return s;
}

void Tunnel::Connect(int index, uint64_t now) {
    auto &l = lanes_[index];
    if (l.fd >= 0 || now < l.retryAt) return;
    l.retryAt = now + 2000000;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) { Log("socket_failed", index, errno); return; }
    if (!Nonblock(fd)) { Close(fd); return; }
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
    auto addr = Address(cfg_.tunnelHost, index == 0 ? cfg_.videoPort : cfg_.controlPort);
    int rc = connect(fd, reinterpret_cast<sockaddr *>(&addr), sizeof(addr));
    if (rc < 0 && errno != EINPROGRESS) { Log("connect_failed", index, errno); Close(fd); return; }
    l.fd = fd;
    l.deadline = now + 5000000;
    l.connected = rc == 0;
    l.rx.reserve(131072); l.tx.reserve(65536);
}

void Tunnel::Disconnect(int index, uint64_t now) {
    auto &l = lanes_[index];
    Log("disconnected", index);
    Close(l.fd);
    l.connected = false;
    // A partial frame belongs to the old byte stream. Never replay it on reconnect.
    l.rx.clear(); l.tx.clear(); l.txOff = 0;
    l.retryAt = now + 2000000;
    std::lock_guard<std::mutex> lock(statsMutex_);
    ++stats_.reconnects;
}

void Tunnel::Run() {
    Log("started", -1);
    while (running_) {
        uint64_t now = NowUs();
        for (int i = 0; i < 2; ++i) {
            if (lanes_[i].fd >= 0 && !lanes_[i].connected && now >= lanes_[i].deadline)
                Disconnect(i, now);
            Connect(i, now);
        }
        pollfd fds[9]{};
        fds[0] = {wake_[0], POLLIN, 0};
        // Service control first, even during a large video burst.
        for (int j = 0; j < 2; ++j) {
            auto &l = lanes_[1 - j];
            short events = POLLIN;
            if (!l.connected || l.txOff < l.tx.size()) events |= POLLOUT;
            fds[j + 1] = {l.fd, events, 0};
        }
        const int order[6]{1, 4, 2, 5, 0, 3};
        for (int j = 0; j < 6; ++j) fds[j + 3] = {udp_[order[j]], POLLIN, 0};
        int ready = poll(fds, 9, 100);
        if (ready < 0) { if (errno == EINTR) continue; break; }
        if (!running_) break;
        for (int j = 0; j < 2; ++j) {
            int index = 1 - j;
            auto &l = lanes_[index];
            short ev = fds[j + 1].revents;
            if (l.fd >= 0 && !l.connected && (ev & (POLLOUT | POLLERR | POLLHUP))) {
                int err = 0; socklen_t len = sizeof(err);
                if (getsockopt(l.fd, SOL_SOCKET, SO_ERROR, &err, &len) != 0 || err != 0) {
                    Log("connect_failed", index, err); Disconnect(index, NowUs());
                } else {
                    l.connected = true;
                    Log("connected", index);
                }
            }
            if (index == 1) {
                for (int k = 0; k < 2; ++k)
                    if (fds[k + 3].revents & POLLIN) ReadUdp(order[k]);
            }
            if (l.fd < 0 || !ev) continue;
            if (ev & POLLIN) ReadLane(index);
            if (l.fd >= 0 && (ev & POLLOUT)) Flush(index);
            if (l.fd >= 0 && ((ev & (POLLERR | POLLNVAL)) || ((ev & POLLHUP) && !(ev & POLLIN))))
                Disconnect(index, NowUs());
        }
        for (int j = 2; j < 6; ++j) if (fds[j + 3].revents & POLLIN) ReadUdp(order[j]);
        {
            std::lock_guard<std::mutex> lock(statsMutex_);
            stats_.videoConnected = lanes_[0].connected;
            stats_.controlConnected = lanes_[1].connected;
            stats_.videoQueue = lanes_[0].tx.size() - lanes_[0].txOff;
            stats_.controlQueue = lanes_[1].tx.size() - lanes_[1].txOff;
        }
    }
    Log("stopped", -1);
}

void Tunnel::PumpControl() {
    // All sockets still have one owner. Check input during video bursts, not
    // only after a whole TCP chunk / UDP batch. Each operation is nonblocking.
    ReadUdp(1);
    ReadUdp(4);
    if (lanes_[1].connected) {
        Flush(1);
        if (lanes_[1].fd >= 0) ReadLane(1);
    }
}

void Tunnel::ReadLane(int index) {
    auto &l = lanes_[index];
    uint8_t buf[65536];
    // Bound each turn by bytes, preserving control/UDP fairness without dropping.
    ssize_t n = recv(l.fd, buf, sizeof(buf), 0);
    if (n < 0 && (Again() || errno == EINTR)) return;
    if (n <= 0) { Disconnect(index, NowUs()); return; }
    l.rx.insert(l.rx.end(), buf, buf + n);
    size_t off = 0;
    int delivered = 0;
    while (l.rx.size() - off >= 3) {
        int ch = l.rx[off];
        size_t size = (static_cast<size_t>(l.rx[off + 1]) << 8) | l.rx[off + 2];
        if (ch > 2 || size > 65507 || (index == 0 ? ch != 0 : ch == 0)) {
            { std::lock_guard<std::mutex> lock(statsMutex_); ++stats_.protocolErrors; }
            Disconnect(index, NowUs()); return;
        }
        if (l.rx.size() - off < size + 3) break;
        Deliver(ch, l.rx.data() + off + 3, size);
        off += size + 3;
        if (index == 0 && ++delivered % 8 == 0) PumpControl();
    }
    if (off) l.rx.erase(l.rx.begin(), l.rx.begin() + off);
}

void Tunnel::Deliver(int ch, const uint8_t *data, size_t size) {
    uint64_t begin = NowUs();
    ssize_t n;
    do {
        n = sendto(udp_[clientSocket_[ch]], data, size, MSG_DONTWAIT,
            reinterpret_cast<sockaddr *>(&clients_[ch]), sizeof(sockaddr_in));
    } while (n < 0 && errno == EINTR);
    // Native kernel completion is observed immediately. No JS pending-send counter.
    std::lock_guard<std::mutex> lock(statsMutex_);
    if (n == static_cast<ssize_t>(size)) { ++stats_.downPkts; stats_.downBytes += size; }
    else { ++stats_.sendErrors; ++stats_.dropped; }
    uint64_t us = NowUs() - begin;
    size_t bucket = 0;
    while (bucket < 31 && (1ULL << bucket) < us) ++bucket;
    ++dispatchHistogram_[bucket];
}

void Tunnel::ReadUdp(int index) {
    uint8_t buf[65507];
    int ch = index % 3, laneIndex = ch == 0 ? 0 : 1;
    auto &l = lanes_[laneIndex];
    for (int i = 0; i < BATCH; ++i) {
        sockaddr_in src{}; socklen_t len = sizeof(src);
        ssize_t n = recvfrom(udp_[index], buf, sizeof(buf), 0, reinterpret_cast<sockaddr *>(&src), &len);
        if (n < 0) { if (errno == EINTR) continue; break; }
        // Learn the complete endpoint per channel, including ENet's ephemeral port,
        // and reply through the exact local address used by the client.
        clients_[ch] = src;
        clientSocket_[ch] = index;
        {
            std::lock_guard<std::mutex> lock(statsMutex_);
            ++stats_.upPkts; stats_.upBytes += n;
        }
        if (!l.connected || (ch == 0 && l.tx.size() - l.txOff > QUEUE_LIMIT)) {
            std::lock_guard<std::mutex> lock(statsMutex_); ++stats_.dropped; continue;
        }
        if (l.txOff) { l.tx.erase(l.tx.begin(), l.tx.begin() + l.txOff); l.txOff = 0; }
        l.tx.push_back(ch); l.tx.push_back((n >> 8) & 0xff); l.tx.push_back(n & 0xff);
        l.tx.insert(l.tx.end(), buf, buf + n);
        if (ch == 0 && (i + 1) % 8 == 0) PumpControl();
    }
    Flush(laneIndex);
}

void Tunnel::Flush(int index) {
    auto &l = lanes_[index];
    if (!l.connected || l.txOff == l.tx.size()) return;
    ssize_t n = send(l.fd, l.tx.data() + l.txOff, l.tx.size() - l.txOff, MSG_NOSIGNAL);
    if (n < 0) {
        if (Again() || errno == EINTR) return;
        Disconnect(index, NowUs()); return;
    }
    l.txOff += n;
    if (l.txOff == l.tx.size()) { l.tx.clear(); l.txOff = 0; }
}
