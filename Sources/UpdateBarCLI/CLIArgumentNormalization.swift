func normalizeCLIArguments(_ arguments: [String]) -> [String] {
    var normalized: [String] = []
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]
        let next: String? = index + 1 < arguments.count
            ? arguments[index + 1]
            : nil

        if let next,
           let normalizedPair = normalizeBooleanFlagValuePair(flag: argument, value: next)
        {
            normalized.append(contentsOf: normalizedPair)
            index += 2
            continue
        }

        if let action = normalizeBooleanAssignmentArgument(argument) {
            switch action {
            case .keep(let value):
                normalized.append(value)
            case .drop:
                break
            }
            index += 1
            continue
        }

        normalized.append(argument)
        index += 1
    }

    return normalized
}

private func normalizeBooleanFlagValuePair(flag: String, value: String) -> [String]? {
    guard isBooleanFlag(flag),
          let boolValue = parseBooleanValue(value)
    else {
        return nil
    }

    return boolValue ? [flag] : []
}

private func normalizeBooleanAssignmentArgument(_ argument: String) -> NormalizedArgument? {
    guard argument.hasPrefix("--"), let equalsRange = argument.firstIndex(of: "=") else {
        return nil
    }

    let key = String(argument[..<equalsRange])
    let value = String(argument[argument.index(after: equalsRange)...]).lowercased()

    switch key {
    case "--json", "--json-stream":
        if trueBooleanValues.contains(value) {
            return .keep(key)
        }
        if falseBooleanValues.contains(value) {
            return .drop
        }
        return .keep(argument)
    default:
        return .keep(argument)
    }
}

private enum NormalizedArgument {
    case keep(String)
    case drop
}

private func isBooleanFlag(_ argument: String) -> Bool {
    jsonBooleanFlags.contains(argument)
}

private func parseBooleanValue(_ value: String) -> Bool? {
    let normalized = value.lowercased()
    if trueBooleanValues.contains(normalized) {
        return true
    }
    if falseBooleanValues.contains(normalized) {
        return false
    }
    return nil
}

private let jsonBooleanFlags: Set<String> = [
    "--json",
    "--json-stream"
]

private let trueBooleanValues: Set<String> = [
    "1",
    "true",
    "t",
    "yes",
    "on"
]

private let falseBooleanValues: Set<String> = [
    "0",
    "false",
    "f",
    "no",
    "off"
]
