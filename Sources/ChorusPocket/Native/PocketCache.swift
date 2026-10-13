import MLX
import MLXFast

public protocol KVCache: AnyObject {
    var offset: Int { get set }
    func update(keys: MLXArray, values: MLXArray) -> (MLXArray, MLXArray)
}
public final class KVCacheSimple: KVCache {
    public var offset = 0
    public var state: [MLXArray] = []
    public init() {}
    @discardableResult public func trim(_ count: Int) -> Int {
        let removed = min(max(0, count), offset)
        offset -= removed
        if offset == 0 { state = [] }
        else if !state.isEmpty { state = state.map { $0[0..., 0..., ..<offset, 0...] } }
        return removed
    }
    public func update(keys: MLXArray, values: MLXArray) -> (MLXArray, MLXArray) {
        let k = state.isEmpty ? keys : concatenated([state[0], keys], axis: 2)
        let v = state.isEmpty ? values : concatenated([state[1], values], axis: 2)
        state = [k, v]; offset += keys.shape[2]
        return (k, v)
    }
}
func createAttentionMask(h: MLXArray, keyLength: Int) -> MLXFast.ScaledDotProductAttentionMaskMode {
    let count = h.shape[1]
    guard count > 1 else { return .none }
    let rows = MLXArray(Array((keyLength - count)..<keyLength)).reshaped([count, 1])
    let cols = MLXArray(Array(0..<keyLength)).reshaped([1, keyLength])
    return .array((rows .< cols).asType(h.dtype) * -1e9)
}
