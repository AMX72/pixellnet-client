package com.hiddify.hiddify.constant

enum class Alert {
    RequestVPNPermission,
    // v0.1.34: VPN permission revoked mid-session (другой VPN взял разрешение,
    // или пользователь сбросил в системных настройках). Отличается от
    // RequestVPNPermission тем, что сервис уже был запущен.
    VpnPermissionRevoked,
    RequestNotificationPermission,
    EmptyConfiguration,
    StartCommandServer,
    CreateService,
    StartService
}