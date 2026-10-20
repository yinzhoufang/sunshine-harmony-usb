#include "tunnel.h"
#include "probe.h"
#include <arpa/inet.h>
#include <napi/native_api.h>

namespace {
Tunnel tunnel;
std::string String(napi_env env, napi_value value) {
    char buf[64]{}; size_t size = 0;
    napi_get_value_string_utf8(env, value, buf, sizeof(buf), &size);
    return std::string(buf, size);
}
int Int(napi_env env, napi_value value) {
    int32_t n = 0; napi_get_value_int32(env, value, &n); return n;
}
bool Ports(napi_env env, napi_value value, std::array<int, 3> &out) {
    uint32_t len = 0;
    if (napi_get_array_length(env, value, &len) != napi_ok || len != 3) return false;
    for (uint32_t i = 0; i < len; ++i) {
        napi_value v; napi_get_element(env, value, i, &v); out[i] = Int(env, v);
        if (out[i] < 1 || out[i] > 65535) return false;
    }
    return true;
}
napi_value Start(napi_env env, napi_callback_info info) {
    size_t argc = 6; napi_value argv[6];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    Config cfg;
    if (argc != 6) { napi_throw_type_error(env, nullptr, "Expected six configuration arguments"); return nullptr; }
    cfg.tunnelHost = String(env, argv[0]); cfg.videoPort = Int(env, argv[1]);
    cfg.controlPort = Int(env, argv[2]); cfg.listenHost = String(env, argv[3]);
    in_addr addr{};
    if (inet_pton(AF_INET, cfg.tunnelHost.c_str(), &addr) != 1 ||
        inet_pton(AF_INET, cfg.listenHost.c_str(), &addr) != 1 ||
        cfg.videoPort < 1 || cfg.videoPort > 65535 || cfg.controlPort < 1 || cfg.controlPort > 65535 ||
        cfg.videoPort == cfg.controlPort || !Ports(env, argv[4], cfg.serverPorts) || !Ports(env, argv[5], cfg.clientPorts)) {
        napi_throw_type_error(env, nullptr, "Invalid IPv4 address or port configuration"); return nullptr;
    }
    int rc = tunnel.Start(cfg);
    napi_value result; napi_create_int32(env, rc, &result); return result;
}
napi_value Stop(napi_env env, napi_callback_info) {
    tunnel.Stop(); napi_value value; napi_get_undefined(env, &value); return value;
}
napi_value Probe(napi_env env, napi_callback_info) {
    napi_value value; napi_create_int32(env, StartProbe(), &value); return value;
}
napi_value EndProbe(napi_env env, napi_callback_info) {
    StopProbe(); napi_value value; napi_get_undefined(env, &value); return value;
}
napi_value Stats(napi_env env, napi_callback_info) {
    auto s = tunnel.Stats(); napi_value out; napi_create_object(env, &out);
    auto number = [&](const char *key, uint64_t n) {
        napi_value v; napi_create_double(env, static_cast<double>(n), &v); napi_set_named_property(env, out, key, v);
    };
    number("upPkts", s.upPkts); number("upBytes", s.upBytes);
    number("downPkts", s.downPkts); number("downBytes", s.downBytes);
    number("dropped", s.dropped); number("sendErrors", s.sendErrors);
    number("reconnects", s.reconnects); number("protocolErrors", s.protocolErrors);
    number("videoQueue", s.videoQueue); number("controlQueue", s.controlQueue);
    number("dispatchP99Us", s.dispatchP99Us);
    number("videoConnected", s.videoConnected); number("controlConnected", s.controlConnected);
    return out;
}
void Cleanup(void *) { StopProbe(); tunnel.Stop(); }
napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor descriptors[] = {
        {"start", nullptr, Start, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stop", nullptr, Stop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getStats", nullptr, Stats, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startProbe", nullptr, Probe, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopProbe", nullptr, EndProbe, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, 5, descriptors);
    napi_add_env_cleanup_hook(env, Cleanup, nullptr);
    return exports;
}
napi_module module = {1, 0, nullptr, Init, "usbtunnel", nullptr, {0}};
}
extern "C" __attribute__((constructor)) void RegisterTunnel() { napi_module_register(&module); }
