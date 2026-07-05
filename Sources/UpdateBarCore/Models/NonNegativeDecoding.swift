func validateNonNegativeDecoded<Key: CodingKey>(
    _ value: Int,
    forKey key: Key,
    in container: KeyedDecodingContainer<Key>
) throws {
    guard value >= 0 else {
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "\(key.stringValue) must be non-negative"
        )
    }
}
