//
//  InputSource.swift
//  Squirrel
//
//  Created by Leo Liu on 5/10/24.
//

// 导入系统基础库和输入法开发工具包
// 就像导入工具箱，里面有处理输入法相关功能的工具
import Foundation
import InputMethodKit

// 定义一个类叫 SquirrelInstaller（鼠须管安装器）
// final 意味着这个类不能被其他类继承，就像最终版本一样
final class SquirrelInstaller {
  // 定义输入模式的枚举（就像给不同的输入法起名字）
  // String 表示这些模式用字符串来表示，CaseIterable 表示可以遍历所有选项
  enum InputMode: String, CaseIterable {
    static let primary = Self.hans  // 设置默认的主要输入模式为简体中文
    case hans = "im.rime.inputmethod.Squirrel.Hans"  // 简体中文输入法的标识符
    case hant = "im.rime.inputmethod.Squirrel.Hant"  // 繁体中文输入法的标识符
  }
  // 用 lazy 修饰的属性，意思是"第一次用到的时候才创建"
  // 这个属性用来存储系统中所有的输入法，就像一个输入法的通讯录
  // [String: TISInputSource]  Key 和 Value的字典,
  private lazy var inputSources: [String: TISInputSource] = {
    // 创建一个空的字典来存储输入法信息, 这个语法是空字典语法
    var inputSources = [String: TISInputSource]()
    var matchingSources = [InputMode: TISInputSource]()
    
    // 从系统获取所有输入法的列表，就像获取电脑上安装的所有输入法
    let sourceList = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
    
    // 遍历每一个输入法，就像翻阅通讯录的每一页
    for inputSource in sourceList {
      // 获取这个输入法的标识符（ID），就像获取每个人的身份证号
      let sourceIDRef = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID)
      guard let sourceID = unsafeBitCast(sourceIDRef, to: CFString?.self) as String? else { continue }
      // print("[DEBUG] Examining input source: \(sourceID)")  // 调试信息（已注释）
      
      // 把这个输入法存储到我们的字典里，用 ID 作为钥匙
      inputSources[sourceID] = inputSource
    }
    return inputSources
  }()

  // 这个函数用来检查哪些输入模式已经被启用了
  // 就像检查家里哪些电器是开着的
  func enabledModes() -> [InputMode] {
    var enabledModes = Set<InputMode>()  // 创建一个集合来存储已启用的模式
    
    // 检查所有的输入模式
    for (mode, inputSource) in getInputSource(modes: InputMode.allCases) {
      // 检查这个输入法是否已经启用，就像检查电器是否插电
      if let enabled = getBool(for: inputSource, key: kTISPropertyInputSourceIsEnabled), enabled {
        enabledModes.insert(mode)  // 如果启用了，就加到集合里
      }
      // 如果所有模式都检查完了，就不用继续了
      if enabledModes.count == InputMode.allCases.count {
        break
      }
    }
    return Array(enabledModes)  // 把集合转换成数组返回
  }

  // 这个函数用来注册输入法到系统中
  // 就像在政府部门登记一个新的服务项目
  func register() {
    let enabledInputModes = enabledModes()  // 先检查哪些模式已经启用
    
    // 如果已经有启用的输入法，就不需要重复注册了
    if !enabledInputModes.isEmpty {
      print("User already registered Squirrel method(s): \(enabledInputModes.map { $0.rawValue })")
      // Already registered.
      return  // 直接返回，不做任何操作
    }
    
    // 向系统注册鼠须管输入法，告诉系统"我们有一个新的输入法"
    TISRegisterInputSource(SquirrelApp.appDir as CFURL)
    print("Registered input source from \(SquirrelApp.appDir)")
  }

  // 这个函数用来启用指定的输入模式
  // modes 参数默认为空数组，意思是如果不指定就使用默认设置
  func enable(modes: [InputMode] = []) {
    let enabledInputModes = enabledModes()  // 检查当前已启用的模式
    
    // 如果已经有启用的输入法，并且用户没有指定特定模式
    if !enabledInputModes.isEmpty && modes.isEmpty {
      print("User already enabled Squirrel method(s): \(enabledInputModes.map { $0.rawValue })")
      // keep user's manually enabled input modes.
      return  // 保持用户手动启用的输入法不变
    }
    
    // 确定要启用哪些模式：如果用户指定了就用指定的，否则用默认的主要模式
    let modesToEnable = modes.isEmpty ? [.primary] : modes
    
    // 逐个启用指定的输入模式
    for (mode, inputSource) in getInputSource(modes: modesToEnable) {
      // 检查这个输入法是否还没有启用
      if let enabled = getBool(for: inputSource, key: kTISPropertyInputSourceIsEnabled), !enabled {
        // 尝试启用这个输入法，就像打开一个开关
        let error = TISEnableInputSource(inputSource)
        print("Enable \(error == noErr ? "succeeds" : "fails") for input source: \(mode.rawValue)")
      }
    }
  }

  // 这个函数用来选择（切换到）指定的输入模式
  // mode 参数是可选的，如果不指定就使用默认的主要模式
  func select(mode: InputMode? = nil) {
    let enabledInputModes = enabledModes()  // 获取当前已启用的模式
    let modeToSelect = mode ?? .primary     // 确定要选择的模式，?? 表示"如果没有指定就用默认的"
    
    // 检查要选择的模式是否已经启用
    if !enabledInputModes.contains(modeToSelect) {
      if mode != nil {
        // 如果用户指定了模式但还没启用，就先启用它
        enable(modes: [modeToSelect])
      } else {
        // 如果默认模式还没启用，提示用户
        print("Default method not enabled yet: \(modeToSelect.rawValue)")
        return
      }
    }
    
    // 尝试选择指定的输入模式
    for (mode, inputSource) in getInputSource(modes: [modeToSelect]) {
      // 检查这个输入法的各种状态
      if let enabled = getBool(for: inputSource, key: kTISPropertyInputSourceIsEnabled),      // 是否已启用
         let selectable = getBool(for: inputSource, key: kTISPropertyInputSourceIsSelectCapable), // 是否可选择
         let selected = getBool(for: inputSource, key: kTISPropertyInputSourceIsSelected),    // 是否已选择
         enabled && selectable && !selected {  // 已启用、可选择、但还没选择
        
        // 执行选择操作，就像从多个频道中选择一个
        let error = TISSelectInputSource(inputSource)
        print("Selection \(error == noErr ? "succeeds" : "fails") for input source: \(mode.rawValue)")
      } else {
        print("Failed to select \(mode.rawValue)")
      }
    }
  }

  // 这个函数用来禁用指定的输入模式
  // modes 参数默认为空，如果不指定就禁用所有模式
  func disable(modes: [InputMode] = []) {
    // 确定要禁用哪些模式：如果没指定就禁用所有，否则禁用指定的
    let modesToDisable = modes.isEmpty ? InputMode.allCases : modes
    
    // 逐个禁用指定的输入模式
    for (mode, inputSource) in getInputSource(modes: modesToDisable) {
      // 检查这个输入法是否当前是启用状态
      if let enabled = getBool(for: inputSource, key: kTISPropertyInputSourceIsEnabled), enabled {
        // 执行禁用操作，就像关闭一个开关
        let error = TISDisableInputSource(inputSource)
        print("Disable \(error == noErr ? "succeeds" : "fails") for input source: \(mode.rawValue)")
      }
    }
  }

  // 这是一个私有的辅助函数，用来根据模式获取对应的输入法对象
  // private 表示只有这个类内部可以使用，就像家里的内部工具
  private func getInputSource(modes: [InputMode]) -> [InputMode: TISInputSource] {
    var matchingSources = [InputMode: TISInputSource]()  // 创建一个字典来存储匹配的结果
    
    // 遍历每个要查找的模式
    for mode in modes {
      // 在我们的输入法通讯录里查找这个模式对应的输入法
      if let inputSource = inputSources[mode.rawValue] {
        matchingSources[mode] = inputSource  // 找到了就存储起来
      }
    }
    return matchingSources  // 返回找到的输入法
  }

  // 这是另一个私有的辅助函数，用来获取输入法的布尔属性（是/否状态）
  // 比如检查输入法是否启用、是否可选择等
  private func getBool(for inputSource: TISInputSource, key: CFString!) -> Bool? {
    // 从输入法对象中获取指定属性的值
    let enabledRef = TISGetInputSourceProperty(inputSource, key)
    
    // 尝试把获取到的值转换成布尔类型（CFBoolean）
    guard let enabled = unsafeBitCast(enabledRef, to: CFBoolean?.self) else { return nil }
    
    // 把 CFBoolean 转换成 Swift 的 Bool 类型并返回
    return CFBooleanGetValue(enabled)
  }
}
