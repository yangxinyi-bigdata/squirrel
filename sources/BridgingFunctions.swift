//
//  BridgingFunctions.swift
//  Squirrel
//
//  Created by Leo Liu on 5/11/24.
//

// 导入系统基础库，这就像导入一个工具箱，里面有很多常用的功能
import Foundation

// 定义一个协议（协议就像一个约定或合同）
// DataSizeable 意思是"可以计算数据大小的"
// 任何遵循这个协议的类型都必须有一个叫 data_size 的属性
protocol DataSizeable {
  // swiftlint:disable:next identifier_name
  var data_size: Int32 { get set } // 用来存储数据大小的数字，Int32 表示32位整数
}

// 下面这些代码是在告诉系统："这些 Rime 相关的结构体都可以计算数据大小"
// 就像给不同的盒子都贴上标签，说明它们都能计算自己的重量
extension RimeContext_stdbool: DataSizeable {} // Rime 上下文（场景信息）
extension RimeTraits: DataSizeable {}         // Rime 特征信息
extension RimeCommit: DataSizeable {}          // Rime 提交信息（用户确认输入的内容）
extension RimeStatus_stdbool: DataSizeable {}  // Rime 状态信息
extension RimeModule: DataSizeable {}          // Rime 模块信息

// 为所有遵循 DataSizeable 协议的类型添加功能
// 这就像给所有贴了标签的盒子都配备了相同的工具
extension DataSizeable {
  // 这个函数用来初始化 Rime 结构体，就像制作一个全新的空盒子
  static func rimeStructInit() -> Self {
    // 在内存中分配空间，就像在仓库里划出一块地方放新盒子
    let valuePointer = UnsafeMutablePointer<Self>.allocate(capacity: 1)
    // Initialize the memory to zero
    // 把这块内存清零，就像把盒子里的灰尘都清理干净
    memset(valuePointer, 0, MemoryLayout<Self>.size)
    // Convert the pointer to a managed Swift variable
    // 把指针转换成 Swift 可以管理的变量，就像给盒子装上智能管理系统
    var value = valuePointer.move()
    valuePointer.deallocate() // 释放指针，就像回收包装材料
    // Initialize data_size property
    // 计算并设置数据大小属性，就像在盒子上贴标签写明重量
    let offset = MemoryLayout.size(ofValue: \Self.data_size)
    value.data_size = Int32(MemoryLayout<Self>.size - offset)
    return value // 返回初始化好的结构体
  }

  // 这个函数用来设置 C 语言字符串
  // C 语言字符串就像老式的标签纸，需要特殊处理
  mutating func setCString(_ swiftString: String, to keypath: WritableKeyPath<Self, UnsafePointer<CChar>?>) {
    swiftString.withCString { cStr in
      // Duplicate the string to create a persisting C string
      // 复制字符串创建一个持久的 C 字符串，就像把内容从便利贴抄写到正式标签上
      let mutableCStr = strdup(cStr)
      // Free the existing string if there is one
      // 如果之前已经有字符串了，就先把它清理掉，就像撕掉旧标签
      if let existing = self[keyPath: keypath] {
        free(UnsafeMutableRawPointer(mutating: existing))
      }
      // 把新的字符串设置到指定位置，就像贴上新标签
      self[keyPath: keypath] = UnsafePointer(mutableCStr)
    }
  }
}

// 自定义一个新的运算符 ?=
// 这个运算符的意思是"如果右边有值，就赋值给左边"
// 就像说"如果有更好的选择，就换成新的"
infix operator ?= : AssignmentPrecedence

// swiftlint:disable:next operator_whitespace
// 第一个版本：左边是普通变量，右边是可选值（可能有值也可能没有）
func ?=<T>(left: inout T, right: T?) {
  if let right = right { // 如果右边确实有值
    left = right        // 就把这个值赋给左边
  }
  // 如果右边没有值，就什么都不做，保持左边原样
}

// swiftlint:disable:next operator_whitespace
// 第二个版本：左边也是可选值，右边也是可选值
func ?=<T>(left: inout T?, right: T?) {
  if let right = right { // 如果右边确实有值
    left = right        // 就把这个值赋给左边
  }
  // 如果右边没有值，就什么都不做，保持左边原样
}

// 为 NSRange（范围）类型添加功能
// NSRange 用来表示文本中的一段范围，比如"第3个字到第8个字"
extension NSRange {
  // 定义一个空的范围，NSNotFound 表示"没找到"，length: 0 表示长度为0
  // 就像说"这个范围是空的，什么都没选中"
  static let empty = NSRange(location: NSNotFound, length: 0)
}

// 为 NSPoint（点坐标）类型添加数学运算功能
// NSPoint 表示屏幕上的一个点，有 x 坐标和 y 坐标
extension NSPoint {
  // += 运算符：把右边的点坐标加到左边的点上
  // 就像把两个位移叠加起来
  static func += (lhs: inout Self, rhs: Self) {
    lhs.x += rhs.x // x 坐标相加
    lhs.y += rhs.y // y 坐标相加
  }
  
  // - 运算符：计算两个点之间的差值（向量）
  // 就像计算从一个地方到另一个地方需要移动多少距离
  static func - (lhs: Self, rhs: Self) -> Self {
    Self.init(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
  }
  
  // -= 运算符：从左边的点减去右边的点
  // 就像从当前位置回退某个距离
  static func -= (lhs: inout Self, rhs: Self) {
    lhs.x -= rhs.x // x 坐标相减
    lhs.y -= rhs.y // y 坐标相减
  }
  
  // * 运算符：把点坐标乘以一个数字（放大或缩小）
  // 就像把一个位移扩大或缩小几倍
  static func * (lhs: Self, rhs: CGFloat) -> Self {
    Self.init(x: lhs.x * rhs, y: lhs.y * rhs)
  }
  
  // / 运算符：把点坐标除以一个数字（缩小）
  // 就像把一个位移缩小几倍
  static func / (lhs: Self, rhs: CGFloat) -> Self {
    Self.init(x: lhs.x / rhs, y: lhs.y / rhs)
  }
  
  // 计算这个点到原点的距离（长度）
  // 使用勾股定理：距离 = √(x² + y²)
  // 就像用尺子测量从原点到这个点的直线距离
  var length: CGFloat {
    sqrt(pow(self.x, 2) + pow(self.y, 2))
  }
}
