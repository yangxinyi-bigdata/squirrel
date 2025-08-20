//
//  SquirrelConfig.swift
//  Squirrel（松鼠输入法）
//
//  Created by Leo Liu on 5/9/24.
//

// 引入 AppKit 框架，这是 macOS 应用程序的基础框架
// 就像是房子的"地基"，为应用程序提供基本功能，包括颜色、窗口等
import AppKit

// 定义一个配置管理类，专门用来管理输入法的各种设置
// final 表示这个类不能被其他类继承，就像一个"最终版本"的配方，不能再修改
final class SquirrelConfig {
  // 获取 Rime 输入法引擎的接口，就像拿到工具箱一样，里面有很多工具可以用
  private let rimeAPI: RimeApi_stdbool = rime_get_api_stdbool().pointee
  
  // 标记配置文件是否已经打开，初始状态是关闭的
  // private(set) 表示只有这个类自己能修改，其他类只能读取
  private(set) var isOpen = false

  // 创建一个缓存字典，用来临时存储已经读取过的配置
  // 就像一个记事本，把常用的信息记下来，下次直接看笔记，不用重新查找
  private var cache: [String: Any] = [:]
  
  // 创建一个 Rime 配置对象，用来和 Rime 引擎交互
  // 就像一台配置读取器，专门用来读取配置文件
  private var config: RimeConfig = .init()
  
  // 创建一个基础配置对象的引用，用来处理配置继承
  // 就像参考父辈的设置，如果当前配置没有，就去基础配置里找
  private var baseConfig: SquirrelConfig?

  // 打开基础配置文件的方法
  // 基础配置文件是输入法的全局设置，影响所有输入方案
  func openBaseConfig() -> Bool {
    // 先关闭当前可能打开的配置文件，避免冲突
    // 就像看书前先把上一本合上
    close()
    
    // 尝试打开名为"squirrel"的基础配置文件
    // &config 表示把配置对象的地址传给函数，让它知道往哪里写数据
    isOpen = rimeAPI.config_open("squirrel", &config)
    
    // 返回是否成功打开
    return isOpen
  }

  // 打开特定输入方案的配置文件
  // 输入方案就是不同的输入法，比如拼音、五笔、仓颉等
  func open(schemaID: String, baseConfig: SquirrelConfig?) -> Bool {
    // 先关闭当前可能打开的配置文件
    close()
    
    // 尝试打开指定 ID 的输入方案配置文件
    isOpen = rimeAPI.schema_open(schemaID, &config)
    
    // 如果成功打开，就记住基础配置对象
    if isOpen {
      self.baseConfig = baseConfig
    }
    
    // 返回是否成功打开
    return isOpen
  }

  // 关闭配置文件的方法
  // 就像看完书后要合上书，释放资源
  func close() {
    // 如果配置文件是打开状态
    if isOpen {
      // 关闭配置文件，释放资源
      _ = rimeAPI.config_close(&config)
      
      // 清空基础配置的引用
      baseConfig = nil
      
      // 标记为已关闭状态
      isOpen = false
    }
  }

  // 析构函数，当这个对象被销毁时会自动调用
  // 就像打扫房间，在搬走之前把一切都收拾干净
  deinit {
    // 确保配置文件被正确关闭
    close()
  }

  // 检查配置文件中是否存在某个配置区域
  // 配置区域就像是书里的章节，用来组织相关的设置项
  func has(section: String) -> Bool {
    // 如果配置文件是打开状态
    if isOpen {
      // 创建一个配置迭代器，就像书签，用来遍历配置项
      var iterator: RimeConfigIterator = .init()
      
      // 尝试开始遍历指定名称的配置区域
      // 如果这个区域存在，就会返回 true
      if rimeAPI.config_begin_map(&iterator, &config, section) {
        // 结束遍历，清理资源
        rimeAPI.config_end(&iterator)
        
        // 找到了这个配置区域，返回 true
        return true
      }
    }
    
    // 没找到这个配置区域，返回 false
    return false
  }

  // 获取布尔类型的配置值（true 或 false）
  // 布尔值就像开关，只有"开"和"关"两种状态
  func getBool(_ option: String) -> Bool? {
    // 先检查缓存中是否已经有这个值
    // 如果有，就直接返回缓存值，不用重新读取
    if let cachedValue = cachedValue(of: Bool.self, forKey: option) {
      return cachedValue
    }
    
    // 准备一个变量来存储读取到的值，默认为 false
    var value = false
    
    // 如果配置文件是打开的，并且成功读取到了布尔值
    if isOpen && rimeAPI.config_get_bool(&config, option, &value) {
      // 把读取到的值存入缓存，下次就不用重新读取了
      cache[option] = value
      
      // 返回读取到的值
      return value
    }
    
    // 如果当前配置文件中没有这个值，就去基础配置中查找
    return baseConfig?.getBool(option)
  }

  // 获取数字类型的配置值（比如字体大小、透明度等）
  // 返回的是 CGFloat 类型，专门用于界面显示的数值
  func getDouble(_ option: String) -> CGFloat? {
    // 先检查缓存中是否已经有这个值
    if let cachedValue = cachedValue(of: Double.self, forKey: option) {
      return cachedValue
    }
    
    // 准备一个变量来存储读取到的值，默认为 0
    var value: Double = 0
    
    // 如果配置文件是打开的，并且成功读取到了数字值
    if isOpen && rimeAPI.config_get_double(&config, option, &value) {
      // 把读取到的值存入缓存
      cache[option] = value
      
      // 返回读取到的值
      return value
    }
    
    // 如果当前配置文件中没有这个值，就去基础配置中查找
    return baseConfig?.getDouble(option)
  }

  // 获取字符串类型的配置值（比如字体名称、颜色值等）
  // 字符串就是文字信息，比如"Arial"、"0xff0000"等
  func getString(_ option: String) -> String? {
    // 先检查缓存中是否已经有这个值
    if let cachedValue = cachedValue(of: String.self, forKey: option) {
      return cachedValue
    }
    
    // 如果配置文件是打开的，并且成功读取到了字符串值
    if isOpen, let value = rimeAPI.config_get_cstring(&config, option) {
      // 把 C 语言的字符串转换成 Swift 的字符串
      let swiftString = String(cString: value)
      
      // 把读取到的值存入缓存
      cache[option] = swiftString
      
      // 返回读取到的值
      return swiftString
    }
    
    // 如果当前配置文件中没有这个值，就去基础配置中查找
    return baseConfig?.getString(option)
  }

  // 获取颜色类型的配置值（比如文字颜色、背景颜色等）
  // 颜色值通常是十六进制字符串，比如 "0xff0000" 表示红色
  func getColor(_ option: String, inSpace colorSpace: SquirrelTheme.RimeColorSpace) -> NSColor? {
    // 先检查缓存中是否已经有这个颜色值
    if let cachedValue = cachedValue(of: NSColor.self, forKey: option) {
      return cachedValue
    }
    
    // 先获取颜色的字符串表示
    if let colorStr = getString(option), 
       // 然后把字符串转换成 NSColor 对象
       let color = color(from: colorStr, inSpace: colorSpace) {
      // 把转换后的颜色对象存入缓存
      cache[option] = color
      
      // 返回颜色对象
      return color
    }
    
    // 如果当前配置文件中没有这个颜色值，就去基础配置中查找
    return baseConfig?.getColor(option, inSpace: colorSpace)
  }

  // 获取特定应用程序的选项配置
  // 有些设置只对特定的应用程序生效，比如只在 Word 中启用某些功能
  func getAppOptions(_ appName: String) -> [String: Bool] {
    // 构建应用程序选项的键名，格式是 "app_options/应用名称"
    let rootKey = "app_options/\(appName)"
    
    // 创建一个字典来存储应用程序的选项
    var appOptions = [String: Bool]()
    
    // 创建一个配置迭代器，用来遍历这个应用程序的所有选项
    var iterator = RimeConfigIterator()
    
    // 开始遍历指定应用程序的配置区域
    _ = rimeAPI.config_begin_map(&iterator, &config, rootKey)
    
    // 逐个读取配置项
    while rimeAPI.config_next(&iterator) {
      // 这是调试用的代码，打印当前读取的选项信息
      // print("[DEBUG] option[\(iterator.index)]: \(String(cString: iterator.key)), path: (\(String(cString: iterator.path))")
      
      // 如果成功获取到选项的键名和路径
      if let key = iterator.key, 
         let path = iterator.path, 
         // 并且成功获取到这个选项的布尔值
         let value = getBool(String(cString: path)) {
        // 把选项存入字典
        appOptions[String(cString: key)] = value
      }
    }
    
    // 结束遍历，清理资源
    rimeAPI.config_end(&iterator)
    
    // 返回应用程序选项字典
    return appOptions
  }
}

// 为 SquirrelConfig 类添加私有扩展
// 私有扩展意味着这些方法只能在当前文件中使用，就像家庭内部的秘密
private extension SquirrelConfig {
  
  // 从缓存中获取指定类型的值
  // 这是一个通用的缓存读取方法，可以读取任何类型的缓存值
  func cachedValue<T>(of: T.Type, forKey key: String) -> T? {
    // 从缓存字典中查找指定键的值
    // as? T 表示尝试将值转换为指定的类型，如果转换失败就返回 nil
    return cache[key] as? T
  }

  // 把颜色字符串转换成 NSColor 对象
  // 颜色字符串通常是十六进制格式，比如 "0xff0000" 表示红色
  func color(from colorStr: String, inSpace colorSpace: SquirrelTheme.RimeColorSpace) -> NSColor? {
    // 尝试匹配带透明度的颜色格式：0xAARRGGBB（AA=透明度，RR=红色，GG=绿色，BB=蓝色）
    if let matched = try? /0x([A-Fa-f0-9]{2})([A-Fa-f0-9]{2})([A-Fa-f0-9]{2})([A-Fa-f0-9]{2})/.wholeMatch(in: colorStr) {
      // 提取匹配到的各个颜色分量
      let (_, alpha, blue, green, red) = matched.output
      
      // 创建带透明度的颜色对象
      // Int(..., radix: 16) 表示将十六进制字符串转换成数字
      return color(alpha: Int(alpha, radix: 16)!, 
                  red: Int(red, radix: 16)!, 
                  green: Int(green, radix: 16)!, 
                  blue: Int(blue, radix: 16)!, 
                  colorSpace: colorSpace)
    } 
    // 如果不是带透明度的格式，尝试匹配不带透明度的格式：0xRRGGBB
    else if let matched = try? /0x([A-Fa-f0-9]{2})([A-Fa-f0-9]{2})([A-Fa-f0-9]{2})/.wholeMatch(in: colorStr) {
      // 提取匹配到的各个颜色分量
      let (_, blue, green, red) = matched.output
      
      // 创建不透明的颜色对象（透明度设为 255，即完全不透明）
      return color(alpha: 255, 
                  red: Int(red, radix: 16)!, 
                  green: Int(green, radix: 16)!, 
                  blue: Int(blue, radix: 16)!, 
                  colorSpace: colorSpace)
    } 
    // 如果两种格式都不匹配，返回 nil（表示颜色字符串格式错误）
    else {
      return nil
    }
  }

  // 根据颜色分量创建 NSColor 对象
  // 这个方法把红、绿、蓝、透明度四个分量组合成一个完整的颜色对象
  func color(alpha: Int, red: Int, green: Int, blue: Int, colorSpace: SquirrelTheme.RimeColorSpace) -> NSColor {
    // 根据不同的色彩空间创建颜色
    switch colorSpace {
    case .displayP3:
      // Display P3 是一种更广的色域，能显示更丰富的颜色
      // 就像是高级的调色盘，能调出更多种颜色
      return NSColor(displayP3Red: CGFloat(red) / 255,         // 红色分量（0-255 转换为 0-1）
                     green: CGFloat(green) / 255,               // 绿色分量
                     blue: CGFloat(blue) / 255,                // 蓝色分量
                     alpha: CGFloat(alpha) / 255)              // 透明度分量
    case .sRGB:
      // sRGB 是标准的色彩空间，大多数显示器都支持
      // 就像是标准的调色盘，颜色显示比较一致
      return NSColor(srgbRed: CGFloat(red) / 255,             // 红色分量（0-255 转换为 0-1）
                     green: CGFloat(green) / 255,               // 绿色分量
                     blue: CGFloat(blue) / 255,                // 蓝色分量
                     alpha: CGFloat(alpha) / 255)              // 透明度分量
    }
  }
}
