import Foundation

enum Fingerprint {
    static func sha256(_ text: String) -> String {
        let digest = SHA256.hash(Array(text.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }
}

private enum SHA256 {
    private static let k: [UInt32] = [
        0x428a_2f98, 0x7137_4491, 0xb5c0_fbcf, 0xe9b5_dba5,
        0x3956_c25b, 0x59f1_11f1, 0x923f_82a4, 0xab1c_5ed5,
        0xd807_aa98, 0x1283_5b01, 0x2431_85be, 0x550c_7dc3,
        0x72be_5d74, 0x80de_b1fe, 0x9bdc_06a7, 0xc19b_f174,
        0xe49b_69c1, 0xefbe_4786, 0x0fc1_9dc6, 0x240c_a1cc,
        0x2de9_2c6f, 0x4a74_84aa, 0x5cb0_a9dc, 0x76f9_88da,
        0x983e_5152, 0xa831_c66d, 0xb003_27c8, 0xbf59_7fc7,
        0xc6e0_0bf3, 0xd5a7_9147, 0x06ca_6351, 0x1429_2967,
        0x27b7_0a85, 0x2e1b_2138, 0x4d2c_6dfc, 0x5338_0d13,
        0x650a_7354, 0x766a_0abb, 0x81c2_c92e, 0x9272_2c85,
        0xa2bf_e8a1, 0xa81a_664b, 0xc24b_8b70, 0xc76c_51a3,
        0xd192_e819, 0xd699_0624, 0xf40e_3585, 0x106a_a070,
        0x19a4_c116, 0x1e37_6c08, 0x2748_774c, 0x34b0_bcb5,
        0x391c_0cb3, 0x4ed8_aa4a, 0x5b9c_ca4f, 0x682e_6ff3,
        0x748f_82ee, 0x78a5_636f, 0x84c8_7814, 0x8cc7_0208,
        0x90be_fffa, 0xa450_6ceb, 0xbef9_a3f7, 0xc671_78f2,
    ]

    static func hash(_ bytes: [UInt8]) -> [UInt8] {
        var message = bytes
        let bitLength = UInt64(message.count * 8)
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0)
        }
        message += stride(from: 56, through: 0, by: -8).map {
            UInt8((bitLength >> UInt64($0)) & 0xff)
        }

        var h0: UInt32 = 0x6a09_e667
        var h1: UInt32 = 0xbb67_ae85
        var h2: UInt32 = 0x3c6e_f372
        var h3: UInt32 = 0xa54f_f53a
        var h4: UInt32 = 0x510e_527f
        var h5: UInt32 = 0x9b05_688c
        var h6: UInt32 = 0x1f83_d9ab
        var h7: UInt32 = 0x5be0_cd19

        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            var w = Array(repeating: UInt32(0), count: 64)
            for index in 0..<16 {
                let base = chunkStart + index * 4
                w[index] =
                    UInt32(message[base]) << 24
                    | UInt32(message[base + 1]) << 16
                    | UInt32(message[base + 2]) << 8
                    | UInt32(message[base + 3])
            }
            for index in 16..<64 {
                let s0 =
                    rotateRight(w[index - 15], 7) ^ rotateRight(w[index - 15], 18)
                    ^ (w[index - 15] >> 3)
                let s1 =
                    rotateRight(w[index - 2], 17) ^ rotateRight(w[index - 2], 19)
                    ^ (w[index - 2] >> 10)
                w[index] = w[index - 16] &+ s0 &+ w[index - 7] &+ s1
            }

            var a = h0
            var b = h1
            var c = h2
            var d = h3
            var e = h4
            var f = h5
            var g = h6
            var h = h7

            for index in 0..<64 {
                let s1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25)
                let ch = (e & f) ^ ((~e) & g)
                let temp1 = h &+ s1 &+ ch &+ k[index] &+ w[index]
                let s0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ maj
                h = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }

            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e
            h5 = h5 &+ f
            h6 = h6 &+ g
            h7 = h7 &+ h
        }

        var output: [UInt8] = []
        for word in [h0, h1, h2, h3, h4, h5, h6, h7] {
            output.append(UInt8((word >> 24) & 0xff))
            output.append(UInt8((word >> 16) & 0xff))
            output.append(UInt8((word >> 8) & 0xff))
            output.append(UInt8(word & 0xff))
        }
        return output
    }

    private static func rotateRight(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value >> count) | (value << (32 - count))
    }
}
