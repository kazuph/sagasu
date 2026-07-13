#!/usr/bin/env swift

import Foundation

let notificationName = Notification.Name("com.kazuph.sagasu.debug.windowCommand")

guard CommandLine.arguments.count == 2 else {
    fputs("usage: send-window-command.swift <command>\n", stderr)
    exit(64)
}

let command = CommandLine.arguments[1]
let allowedCommands = Set([
    "bottomHalf",
    "centerThird",
    "leftHalf",
    "maximize",
    "nextDisplay",
    "previousDisplay",
    "rightHalf",
    "topHalf"
])

guard allowedCommands.contains(command) else {
    fputs("unknown command: \(command)\n", stderr)
    exit(64)
}

DistributedNotificationCenter.default().postNotificationName(
    notificationName,
    object: nil,
    userInfo: ["command": command],
    deliverImmediately: true
)
