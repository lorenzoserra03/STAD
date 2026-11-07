import CoreAudio

nonisolated struct AudioDevice: Identifiable, Hashable, Sendable {
    let id: AudioDeviceID
    let name: String
    let inputChannels: Int
    let outputChannels: Int
}

nonisolated enum AudioDevices {
    static func all() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.map { id in
            AudioDevice(id: id, name: name(of: id),
                        inputChannels: channelCount(of: id, scope: kAudioObjectPropertyScopeInput),
                        outputChannels: channelCount(of: id, scope: kAudioObjectPropertyScopeOutput))
        }
    }

    /// The tester is a class-compliant USB codec (TI/Burr-Brown) that macOS lists as
    /// "USB AUDIO  CODEC", usually as two devices: one for output, one for input.
    static func findTester(in devices: [AudioDevice] = all()) -> (input: AudioDevice, output: AudioDevice)? {
        let candidates = devices.filter { isTesterName($0.name) }
        guard let input = candidates.first(where: { $0.inputChannels >= 2 }),
              let output = candidates.first(where: { $0.outputChannels >= 2 }) else { return nil }
        return (input, output)
    }

    static func isTesterName(_ name: String) -> Bool {
        let normalized = name.uppercased().split(separator: " ").joined(separator: " ")
        return normalized.hasPrefix("USB AUDIO CODEC") || normalized.hasPrefix("USB AUDIO DEVICE")
    }

    private static func name(of id: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue() else { return "?" }
        return value as String
    }

    private static func channelCount(of id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
