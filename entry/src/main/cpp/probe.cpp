#include "probe.h"
#include <array>
#include <atomic>
#include <thread>
#include <arpa/inet.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>
#include <cerrno>
#include <cstring>
#include <hilog/log.h>

namespace {
std::atomic<bool> active{false};
std::thread worker;
std::array<int, 3> clients{{-1, -1, -1}};
void Run() {
    const int ports[3]{48998, 48999, 49000};
    pollfd fds[3]{};
    for (int ch = 0; ch < 3; ++ch) fds[ch] = {clients[ch], POLLIN, 0};
    uint8_t buf[65507];
    // Send the discovery marker repeatedly until the bridge has started.
    int ticks = 0;
    while (active) {
        if (ticks++ % 10 == 0) {
            const char hello[] = "USBPROBE";
            for (int ch = 0; ch < 3; ++ch) {
                sockaddr_in dst{}; dst.sin_family = AF_INET;
                dst.sin_port = htons(ports[ch]); inet_pton(AF_INET, "127.0.0.2", &dst.sin_addr);
                sendto(clients[ch], hello, 8, 0, reinterpret_cast<sockaddr *>(&dst), sizeof(dst));
            }
        }
        if (poll(fds, 3, 100) < 0 && errno != EINTR) break;
        for (int ch : {1, 2, 0}) {
            if (!(fds[ch].revents & POLLIN)) continue;
            for (int i = 0; i < 64; ++i) {
                sockaddr_in src{}; socklen_t len = sizeof(src);
                ssize_t n = recvfrom(clients[ch], buf, sizeof(buf), MSG_DONTWAIT,
                    reinterpret_cast<sockaddr *>(&src), &len);
                if (n < 0) break;
                // Only reflect diagnostic packets. Never reflect a real RTP/ENet stream.
                if (n >= 4 && std::memcmp(buf, "USBP", 4) == 0)
                    sendto(clients[ch], buf, n, 0, reinterpret_cast<sockaddr *>(&src), len);
            }
        }
    }
}
}
void StopProbe() {
    active = false;
    if (worker.joinable()) worker.join();
    for (auto &fd : clients) { if (fd >= 0) close(fd); fd = -1; }
}
int StartProbe() {
    StopProbe();
    for (int ch = 0; ch < 3; ++ch) {
        clients[ch] = socket(AF_INET, SOCK_DGRAM, 0);
        sockaddr_in addr{}; addr.sin_family = AF_INET;
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);
        int buf = 8 * 1024 * 1024;
        setsockopt(clients[ch], SOL_SOCKET, SO_RCVBUF, &buf, sizeof(buf));
        if (clients[ch] < 0 || bind(clients[ch], reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) != 0) {
            int err = errno; StopProbe(); return err;
        }
    }
    active = true;
    worker = std::thread(Run);
    OH_LOG_Print(LOG_APP, LOG_INFO, 0x0001, "UsbTunnel", "USBPROBE enabled; diagnostic echo clients only");
    return 0;
}
