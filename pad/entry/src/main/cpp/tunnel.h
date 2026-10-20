#pragma once
#include <array>
#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include <netinet/in.h>

struct Config {
    std::string tunnelHost, listenHost;
    int videoPort = 47997, controlPort = 47996;
    std::array<int, 3> serverPorts{48998, 48999, 49000};
    std::array<int, 3> clientPorts{47998, 47999, 48000};
};
struct Snapshot {
    uint64_t upPkts = 0, upBytes = 0, downPkts = 0, downBytes = 0;
    uint64_t dropped = 0, sendErrors = 0, reconnects = 0, protocolErrors = 0;
    uint64_t videoQueue = 0, controlQueue = 0, dispatchP99Us = 0;
    bool videoConnected = false, controlConnected = false;
};

// A single native worker owns every media socket. No callbacks into ArkTS.
class Tunnel {
public:
    ~Tunnel() { Stop(); }
    int Start(const Config &cfg);
    void Stop();
    Snapshot Stats();
private:
    struct Lane {
        int fd = -1;
        bool connected = false;
        uint64_t retryAt = 0, deadline = 0;
        std::vector<uint8_t> rx, tx;
        size_t txOff = 0;
    };
    Config cfg_;
    std::array<int, 6> udp_{{-1, -1, -1, -1, -1, -1}};
    std::array<sockaddr_in, 3> clients_{};
    std::array<int, 3> clientSocket_{{0, 1, 2}};
    std::array<Lane, 2> lanes_;
    int wake_[2]{-1, -1};
    std::atomic<bool> running_{false};
    std::thread worker_;
    std::mutex statsMutex_;
    Snapshot stats_;
    std::array<uint64_t, 32> dispatchHistogram_{};
    void Run();
    void Connect(int index, uint64_t now);
    void Disconnect(int index, uint64_t now);
    void ReadLane(int index);
    void PumpControl();
    void Flush(int index);
    void ReadUdp(int index);
    void Deliver(int ch, const uint8_t *data, size_t size);
    void Cleanup();
};
