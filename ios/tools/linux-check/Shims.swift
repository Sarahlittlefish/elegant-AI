// 只给 Linux 检查用：Linux 上没有 Combine，这里补两个空壳，iPad 上用的是苹果自带的。
protocol ObservableObject: AnyObject {}
@propertyWrapper struct Published<Value> {
    var wrappedValue: Value
    init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
