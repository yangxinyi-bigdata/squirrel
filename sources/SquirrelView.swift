//
//  SquirrelView.swift
//  Squirrel
//
//  Created by Leo Liu on 5/9/24.
//
// ========================================================================
// 🎨 松鼠输入法视图渲染系统 - SquirrelView 核心模块
// ========================================================================
//
// 📋 模块功能概述：
// 这是松鼠输入法的"绘图引擎"，负责将文本数据转换为用户看到的精美界面。
// 就像一个专业的画家，它拿着SquirrelTheme提供的"颜料"和SquirrelPanel传来的"草图"，
// 在屏幕这张"画布"上绘制出最终的候选字窗口。
//
// 🏗️ 核心职责：
// 1. 🖼️ 图形渲染：绘制窗口背景、边框、圆角、阴影等视觉效果
// 2. 📝 文本渲染：处理富文本的显示，包括字体、颜色、对齐等
// 3. 🎯 高亮效果：绘制候选字的选中高亮、悬停效果
// 4. 📄 分页指示：绘制翻页按钮和页码信息
// 5. 📐 几何计算：计算文本位置、窗口尺寸、点击区域
// 6. 🔄 布局管理：处理垂直/水平布局的坐标转换
// 7. 🖱️ 交互检测：将鼠标点击坐标转换为对应的候选字索引
//
// 🔄 主要工作流程：
// 1. 接收SquirrelPanel传来的富文本和布局参数
// 2. 使用SquirrelTheme提供的样式信息
// 3. 计算各个元素的位置和大小
// 4. 在drawRect中绘制所有视觉元素
// 5. 响应点击事件，返回对应的候选字索引
//
// 🎯 关键特性：
// - 支持垂直/水平两种文本布局
// - 自定义文本换行控制（noBreak属性）
// - 精确的文本几何计算
// - 平滑的高亮动画效果
// - 智能的分页按钮布局
// - 独立的预编辑和候选区域滚动
//
// 📐 几何系统：
// - contentRect: 计算文本内容的边界框
// - click: 将屏幕坐标转换为文本索引
// - drawRect: 在指定区域绘制界面
//
// 🎨 渲染层次（从底到顶）：
// 1. 窗口形状和背景色
// 2. 边框和阴影
// 3. 文本内容
// 4. 高亮背景
// 5. 分页按钮
//
// 🎯 在输入法架构中的位置：
// SquirrelPanel → SquirrelView ← SquirrelTheme
// (界面协调)     (图形渲染)   (样式提供)
//
// ========================================================================

// 导入 AppKit，这是 macOS 应用界面开发的核心库
// 就像导入一个绘画工具箱，里面有各种绘制界面的工具
import AppKit

// 定义一个私有的文本布局代理类
// 这个类就像一个文本排版师，负责决定文字应该如何换行
private class SquirrelLayoutDelegate: NSObject, NSTextLayoutManagerDelegate {
  // 这个函数决定是否应该在某个位置换行
  // 就像决定一行文字写满了是否要另起一行
  // 
  // 参数说明：
  // - textLayoutManager: 文本布局管理器，负责管理整个文本的布局和排版
  // - location: 当前考虑换行的文本位置，这是一个抽象的文本位置对象
  // - hyphenating: 是否允许连字符换行（如英文单词中间加横线换行），在中文输入法中通常为false
  // 
  // 返回值：
  // - true: 允许在此位置换行，文本会在这里折断到下一行
  // - false: 禁止在此位置换行，强制保持文本在同一行
  func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, shouldBreakLineBefore location: any NSTextLocation, hyphenating: Bool) -> Bool {
    // 计算当前位置在文本中的索引
    // 将抽象的文本位置(NSTextLocation)转换为具体的数字索引(Int)
    let index = textLayoutManager.offset(from: textLayoutManager.documentRange.location, to: location)
    
    // 检查当前位置的文本是否有 "noBreak" 属性（不换行属性）
    // 这是一个自定义属性，用来标记某些文本区域不允许换行（比如短的候选词）
    if let attributes = textLayoutManager.textContainer?.textView?.textContentStorage?.attributedString?.attributes(at: index, effectiveRange: nil),
       let noBreak = attributes[.noBreak] as? Bool, noBreak {
      return false  // 如果设置了不换行，就返回 false（不要换行）
    }
    return true  // 否则允许换行（默认行为）
  }
}

// 扩展 NSAttributedString.Key，添加自定义的文本属性
// 就像给文本属性工具箱添加一个新工具
extension NSAttributedString.Key {
  static let noBreak = NSAttributedString.Key("noBreak")  // 定义"不换行"属性
}

// 定义鼠须管视图类，这是候选字窗口的核心显示组件
// final 表示这个类不能被继承，NSView 是 macOS 视图的基类
// 这个类就像一个特殊的画布，专门用来绘制输入法候选字
final class SquirrelView: NSView {
  // 调试总开关：打印关键几何/路径计算日志
  private let DEBUG_LAYOUT_LOGS = true
  // 类的属性定义，就像这个视图的各种特征和工具
  // 拆分为两个独立区域的视图
  let preeditTextView: NSTextView
  let preeditScrollView: NSScrollView
  let candidateTextView: NSTextView
  let candidateScrollView: NSScrollView
  // 保持向后兼容的别名（默认指向候选区）
  var textView: NSTextView { candidateTextView }
  var scrollView: NSScrollView { candidateScrollView }

  private let squirrelLayoutDelegate: SquirrelLayoutDelegate  // 文本布局代理
  var candidateRanges: [NSRange] = []         // 候选字在文本中的位置范围列表
  var hilightedIndex = 0                      // 当前高亮（选中）的候选字索引
  var preeditRange: NSRange = .empty          // 预编辑文本的范围
  var canPageUp: Bool = false                 // 是否可以向上翻页
  var canPageDown: Bool = false               // 是否可以向下翻页
  var highlightedPreeditRange: NSRange = .empty  // 预编辑文本中高亮部分的范围
  var separatorWidth: CGFloat = 0             // 分隔符的宽度
  var shape = CAShapeLayer()                  // 形状图层，用于绘制面板的形状
  private var downPath: CGPath?               // 向下翻页按钮的路径
  private var upPath: CGPath?                 // 向上翻页按钮的路径

  // 主题相关的属性
  var lightTheme = SquirrelTheme()            // 浅色主题配置
  var darkTheme = SquirrelTheme()             // 深色主题配置
  
  // 计算属性：获取当前应该使用的主题
  var currentTheme: SquirrelTheme {
    // 如果是深色模式并且深色主题可用，就用深色主题，否则用浅色主题
    if isDark && darkTheme.available { darkTheme } else { lightTheme }
  }
  
  // 以下是一些便捷访问属性，就像主题和文本系统的快捷方式
  var textLayoutManager: NSTextLayoutManager {
    textView.textLayoutManager!               // 文本布局管理器
  }
  var textContentStorage: NSTextContentStorage {
    textView.textContentStorage!             // 文本内容存储器
  }
  var textContainer: NSTextContainer {
    textLayoutManager.textContainer!         // 文本容器
  }

  // 初始化函数：创建一个新的鼠须管输入法候选窗口视图
  // 参数 frameRect（框架矩形）：指定视图的初始位置和尺寸
  override init(frame frameRect: NSRect) {
    
    // ========== 第一步：创建核心组件 ==========
    squirrelLayoutDelegate = SquirrelLayoutDelegate()  // 创建布局代理：负责处理文本布局和排版逻辑
    
    // 创建预编辑文本视图（拼音输入区域）
    preeditTextView = NSTextView(frame: frameRect)     // 显示用户正在输入的拼音
    preeditScrollView = NSScrollView(frame: frameRect) // 预编辑文本的滚动容器
    
    // 创建候选词文本视图（候选词列表区域）
    candidateTextView = NSTextView(frame: frameRect)     // 显示候选词列表
    candidateScrollView = NSScrollView(frame: frameRect) // 候选词的滚动容器
    
    // ========== 第二步：统一配置文本视图的基础属性 ==========
    for tv in [preeditTextView, candidateTextView] {
      // drawsBackground（绘制背景）= false：不绘制默认的白色背景，保持透明
      tv.drawsBackground = false
      
      // isEditable（可编辑性）= false：禁止用户直接编辑文本内容
      tv.isEditable = false
      
      // isSelectable（可选择性）= false：禁止用户选择文本
      tv.isSelectable = false
      
      // textLayoutManager.delegate（文本布局管理器代理）：设置自定义布局代理
      tv.textLayoutManager?.delegate = squirrelLayoutDelegate
    }
    
    // ========== 第三步：调用父类初始化 ==========
    super.init(frame: frameRect)  // 初始化 NSView 的基础功能
    
    // ========== 第四步：配置文本容器的细节 ==========
    // lineFragmentPadding（行片段内边距）= 0：移除文本左右两侧的默认边距
    candidateTextView.textContainer?.lineFragmentPadding = 0
    preeditTextView.textContainer?.lineFragmentPadding = 0
    
    // ========== 第五步：配置视图层级属性 ==========
    // wantsLayer（需要图层）= true：启用 Core Animation 图层支持，提升渲染性能
    self.wantsLayer = true
    
    // masksToBounds（遮罩边界）= true：确保子视图内容不会超出父视图边界显示
    self.layer?.masksToBounds = true
    
    // autoresizingMask（自动调整尺寸掩码）：当父视图尺寸改变时，自动调整宽度和高度
    self.autoresizingMask = [.width, .height]

    // ========== 第六步：统一配置滚动视图的属性 ==========
    for sv in [preeditScrollView, candidateScrollView] {
      // drawsBackground（绘制背景）= false：滚动视图不绘制背景，保持透明
      sv.drawsBackground = false
      
      // hasVerticalScroller（有垂直滚动条）= true：当内容超出高度时显示垂直滚动条
      sv.hasVerticalScroller = true
      
      // hasHorizontalScroller（有水平滚动条）= false：不显示水平滚动条
      sv.hasHorizontalScroller = false
      
      // scrollerStyle（滚动条样式）= .overlay：使用覆盖式滚动条（半透明，不占用空间）
      sv.scrollerStyle = .overlay
      
      // borderType（边框类型）= .noBorder：不显示边框
      sv.borderType = .noBorder
      
      // autohidesScrollers（自动隐藏滚动条）= true：不滚动时自动隐藏滚动条
      sv.autohidesScrollers = true
      
      // usesPredominantAxisScrolling（使用主轴滚动）= true：优化滚动体验，主要沿一个方向滚动
      sv.usesPredominantAxisScrolling = true
    }
    
    // ========== 第七步：建立滚动视图与文本视图的关联关系 ==========
    // documentView（文档视图）：设置滚动视图要显示和滚动的内容视图
    preeditScrollView.documentView = preeditTextView       // 预编辑滚动视图显示预编辑文本
    candidateScrollView.documentView = candidateTextView   // 候选词滚动视图显示候选词文本

    // ========== 第八步：设置滚动事件监听 ==========
    // 目的：当用户滚动时，及时重绘视图以保持高亮背景与文本内容的位置同步
    
    // postsBoundsChangedNotifications（发送边界改变通知）= true：当滚动位置改变时发送通知
    preeditScrollView.contentView.postsBoundsChangedNotifications = true
    candidateScrollView.contentView.postsBoundsChangedNotifications = true
    
    // 添加通知观察者：监听滚动视图的边界改变事件
    // selector（选择器）：指定处理通知的方法
    // name（通知名称）：NSView.boundsDidChangeNotification 表示视图边界已改变
    // object（对象）：指定监听哪个视图的通知
    NotificationCenter.default.addObserver(
      self,  // 观察者：当前视图对象
      selector: #selector(handleClipViewBoundsChanged(_:)),  // 处理方法：边界改变时调用
      name: NSView.boundsDidChangeNotification,  // 通知类型：边界改变通知
      object: preeditScrollView.contentView      // 监听对象：预编辑滚动视图的内容视图
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleClipViewBoundsChanged(_:)),
      name: NSView.boundsDidChangeNotification,
      object: candidateScrollView.contentView    // 监听对象：候选词滚动视图的内容视图
    )

    // ========== 第九步：配置文本视图的尺寸调整行为 ==========
    // 目的：让文本在垂直方向可以无限扩展，超出部分由滚动容器进行裁切和滚动
    for tv in [preeditTextView, candidateTextView] {
      // isVerticallyResizable（垂直可调整尺寸）= true：允许文本视图垂直方向自动调整高度
      tv.isVerticallyResizable = true
      
      // isHorizontallyResizable（水平可调整尺寸）= false：禁止水平方向调整，固定宽度
      tv.isHorizontallyResizable = false
      
      // 配置文本容器的跟踪和尺寸属性
      if let container = tv.textContainer {
        // widthTracksTextView（宽度跟踪文本视图）= true：容器宽度跟随文本视图宽度变化
        container.widthTracksTextView = true
        
        // heightTracksTextView（高度跟踪文本视图）= false：容器高度不跟随文本视图，允许无限扩展
        container.heightTracksTextView = false
        
        // containerSize（容器尺寸）：设置文本容器的尺寸
        // 宽度使用传入的框架宽度，高度设为最大值以允许无限垂直扩展
        container.containerSize = NSSize(
          width: frameRect.width,                    // 宽度：使用父视图的宽度
          height: CGFloat.greatestFiniteMagnitude    // 高度：设为最大可能值，实现无限扩展
        )
      }
    }

  // 注意：scrollView 不在此处添加为子视图，由面板负责将其加入层级
  }
  
  // 必需的初始化器（从 Interface Builder 加载时使用）
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")  // 不支持从 Storyboard 创建
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func handleClipViewBoundsChanged(_ notification: Notification) {
    // 滚动时请求重绘，使蓝色高亮背景与文本滚动同步
  // 仅触发重绘，不修改 textView 的 bounds/frame，避免缩放态叠加
  self.needsDisplay = true
  }

  // 重写坐标系属性，设置为翻转坐标系
  // 这让坐标原点在左上角而不是左下角，更符合屏幕显示习惯
  override var isFlipped: Bool {
    true
  }
  
  // 计算属性：检测当前是否为深色模式
  var isDark: Bool {
    // 获取系统当前外观，检查是否匹配深色外观
    NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
  }

  // ========== 滚动偏移量相关属性 ==========
  // 用于获取当前滚动视图的滚动位置，将文档坐标转换为可见区域坐标
  
  // scrollOffset（滚动偏移量）：通用的滚动偏移量获取属性
  // 为了保持向后兼容性，默认返回候选词区域的滚动偏移量
  // NSPoint：表示二维点坐标，包含 x（水平位移）和 y（垂直位移）
  var scrollOffset: NSPoint { // 兼容旧逻辑，等同候选区
    return candidateScrollView.contentView.bounds.origin
  }
  
  // candidateScrollOffset（候选词滚动偏移量）：获取候选词列表的当前滚动位置
  // 
  // 【关键概念解析：bounds.origin】
  // bounds：表示视图内容区域的边界矩形，包含 origin（原点）和 size（尺寸）
  // origin：矩形的"原点"，即左上角的坐标位置
  // 
  // 在滚动视图中，origin 的含义：
  // - origin.x：水平滚动偏移量（向右滚动时增加，向左滚动时减少）
  // - origin.y：垂直滚动偏移量（向下滚动时增加，向上滚动时减少）
  // 
  // 具体例子：
  // - 未滚动时：origin = (0, 0) - 显示文档的最开始部分
  // - 向下滚动100像素后：origin = (0, 100) - 文档向上移动了100像素
  // - 向右滚动50像素后：origin = (50, 100) - 文档向左移动了50像素
  // 
  // 可以这样理解：origin 表示"可见窗口"在整个文档中的位置
  // 就像透过一个固定大小的窗户看一张大报纸，origin 告诉我们窗户当前对准报纸的哪个位置
  var candidateScrollOffset: NSPoint { candidateScrollView.contentView.bounds.origin }
  
  // preeditScrollOffset（预编辑滚动偏移量）：获取预编辑区域（拼音输入区）的当前滚动位置
  var preeditScrollOffset: NSPoint { preeditScrollView.contentView.bounds.origin }
  
  // preeditFrameOriginY（预编辑框架原点Y坐标）：获取预编辑滚动视图在父视图中的垂直位置
  // frame.origin.y：视图在父视图坐标系中的Y坐标（从父视图顶部开始计算）
  private var preeditFrameOriginY: CGFloat { preeditScrollView.frame.origin.y }
  
  // candidateFrameOriginY（候选词框架原点Y坐标）：获取候选词滚动视图在父视图中的垂直位置
  private var candidateFrameOriginY: CGFloat { candidateScrollView.frame.origin.y }

  // ========== 文本范围转换工具函数 ==========
  // 在 macOS 文本系统中，有两种表示文本范围的方式：
  // 1. NSRange：传统方式，使用整数位置和长度（location + length）
  // 2. NSTextRange：现代方式，使用抽象位置对象，更灵活和准确
  
  // convert（转换函数）：将候选词区域的 NSRange 转换为 NSTextRange
  // 参数 range（范围）：要转换的文本范围，包含位置(location)和长度(length)
  // 返回值：转换后的 NSTextRange 对象，如果转换失败则返回 nil
  func convert(range: NSRange) -> NSTextRange? {
    // guard 语句：安全检查，如果条件不满足则提前返回
    // NSRange.empty：表示空范围（位置0，长度0），对于空范围无需转换
    guard range != .empty else { return nil }  // 如果是空范围，返回 nil
    
    // ========== 第一步：计算起始位置 ==========
    // textLayoutManager（文本布局管理器）：负责管理文本的布局和位置计算
    // documentRange.location：文档的起始位置（通常是文档开头）
    // offsetBy：从指定位置偏移指定的字符数量
    // range.location：NSRange 中的起始位置（从0开始计数）
    guard let startLocation = candidateTextView.textLayoutManager?.location(
      candidateTextView.textLayoutManager!.documentRange.location,  // 从文档开头开始
      offsetBy: range.location  // 偏移到 NSRange 指定的起始位置
    ) else { return nil }  // 如果无法计算起始位置，返回 nil
    
    // ========== 第二步：计算结束位置 ==========
    // 从起始位置再偏移 range.length 个字符，得到结束位置
    // range.length：NSRange 中的长度（要选择的字符数量）
    guard let endLocation = candidateTextView.textLayoutManager?.location(
      startLocation,          // 从刚才计算的起始位置开始
      offsetBy: range.length  // 偏移指定的长度
    ) else { return nil }  // 如果无法计算结束位置，返回 nil
    
    // ========== 第三步：创建并返回文本范围 ==========
    // NSTextRange：使用起始位置和结束位置创建新式文本范围对象
    // location：范围的起始位置，end：范围的结束位置
    return NSTextRange(location: startLocation, end: endLocation)
  }

  // convertPreedit（预编辑转换函数）：专门用于预编辑区域的 NSRange 到 NSTextRange 转换
  // 功能与 convert 函数相同，但操作的是预编辑文本视图而不是候选词文本视图
  // 参数 range（范围）：预编辑区域中要转换的文本范围
  // 返回值：转换后的 NSTextRange 对象，用于预编辑区域的文本操作
  func convertPreedit(range: NSRange) -> NSTextRange? {
    // 安全检查：如果是空范围，无需转换
    guard range != .empty else { return nil }
    
    // 计算预编辑区域的起始位置
    // 使用 preeditTextView 的文本布局管理器进行位置计算
    guard let startLocation = preeditTextView.textLayoutManager?.location(
      preeditTextView.textLayoutManager!.documentRange.location,  // 预编辑文档的起始位置
      offsetBy: range.location  // 偏移到指定起始位置
    ) else { return nil }
    
    // 计算预编辑区域的结束位置
    guard let endLocation = preeditTextView.textLayoutManager?.location(
      startLocation,          // 从起始位置开始
      offsetBy: range.length  // 偏移指定长度
    ) else { return nil }
    
    // 创建并返回预编辑区域的文本范围
    return NSTextRange(location: startLocation, end: endLocation)
  }

  // ========== 内容区域计算相关函数 ==========
  // 这些函数用于计算文本内容在屏幕上占用的矩形区域，是布局和渲染的基础
  
  // contentRect（内容矩形）：获取包含所有文本内容的矩形区域
  // 注意：这是一个计算成本较高的操作，类似于测量一张纸上所有文字占用的总面积
  // NSRect：表示矩形区域，包含位置(origin)和尺寸(size)
  var contentRect: NSRect {
    // 初始化为零矩形（位置0,0，尺寸0x0）
    var rect: NSRect = .zero
    
    // ========== 处理候选词文本区域 ==========
    // textLayoutManager（文本布局管理器）：负责文本的布局计算和渲染
    if let tlm = candidateTextView.textLayoutManager {
      // documentRange：整个文档的文本范围（从开头到结尾）
      let r = contentRect(range: tlm.documentRange)
      
      // 安全检查：确保计算出的矩形尺寸是有限的数值
      // isFinite：检查浮点数是否为有限值（不是无穷大或NaN）
      if r.width.isFinite && r.height.isFinite { 
        // union（联合）：将两个矩形合并成一个包含两者的最小矩形
        rect = rect.union(r) 
      }
    }
    
    // ========== 处理预编辑文本区域 ==========
    if let tlm = preeditTextView.textLayoutManager {
      // 使用专门的预编辑内容矩形计算函数
      let r = contentRectPreedit(range: tlm.documentRange)
      
      // 同样进行安全检查和矩形合并
      if r.width.isFinite && r.height.isFinite { 
        rect = rect.union(r) 
      }
    }
    
    // 返回包含所有文本内容的最终矩形
    return rect
  }
  
  // contentRect（指定范围内容矩形）：计算指定文本范围在屏幕上占用的矩形区域
  // 这个函数会遍历文本段，计算每个段的位置，然后找出包含所有段的边界矩形
  // 参数 range（范围）：要计算矩形的文本范围（NSTextRange 对象）
  // 返回值：包含指定文本范围的矩形区域
  func contentRect(range: NSTextRange) -> NSRect {
    // ========== 初始化边界值 ==========
    // 使用极值初始化，这样第一次比较时会被实际值替换
    // swiftlint:disable:next identifier_name  // 禁用变量命名检查（x0, y0 等简短名称是合理的）
    var x0 = CGFloat.infinity,      // 左边界：初始为正无穷，找最小值
        x1 = -CGFloat.infinity,     // 右边界：初始为负无穷，找最大值
        y0 = CGFloat.infinity,      // 上边界：初始为正无穷，找最小值
        y1 = -CGFloat.infinity      // 下边界：初始为负无穷，找最大值
    
    // ========== 枚举文本段并计算边界 ==========
    // enumerateTextSegments（枚举文本段）：遍历指定范围内的所有文本段
    // type: .standard：使用标准文本段类型
    // options: .rangeNotRequired：不需要精确的范围信息，提高性能
    candidateTextView.textLayoutManager?.enumerateTextSegments(
      in: range,                    // 要枚举的文本范围
      type: .standard,              // 文本段类型：标准段落
      options: .rangeNotRequired    // 枚举选项：不需要精确范围信息
    ) { _, rect, _, _ in
      // 闭包参数说明：
      // 第1个参数：文本段范围（我们不使用，所以用 _ 忽略）
      // 第2个参数 rect：文本段的矩形区域
      // 第3、4个参数：基线和其他信息（我们不使用）
      
      // ========== 坐标转换：从文档坐标转换为视图坐标 ==========
      var rect = rect  // 创建可变副本
      
      // 减去滚动偏移量，将文档坐标转换为可见区域坐标
      // candidateScrollOffset：当前候选词区域的滚动位置
      rect.origin.x -= candidateScrollOffset.x  // 调整水平位置
      rect.origin.y -= candidateScrollOffset.y  // 调整垂直位置
      
      // 加上候选词框架的垂直偏移，转换为整个视图的坐标系
      // candidateFrameOriginY：候选词滚动视图在父视图中的Y坐标
      rect.origin.y += candidateFrameOriginY
      
      // ========== 更新边界值 ==========
      // 通过比较每个文本段的边界，找出包含所有段的最小矩形
      x0 = min(rect.minX, x0)  // 更新左边界（最小X坐标）
      x1 = max(rect.maxX, x1)  // 更新右边界（最大X坐标）
      y0 = min(rect.minY, y0)  // 更新上边界（最小Y坐标）
      y1 = max(rect.maxY, y1)  // 更新下边界（最大Y坐标）
      
      return true  // 返回 true 表示继续枚举下一个文本段
    }
    
    // ========== 构造并返回最终矩形 ==========
    // 使用计算出的边界值创建包含所有文本段的矩形
    return NSRect(
      x: x0,              // 左上角X坐标
      y: y0,              // 左上角Y坐标  
      width: x1 - x0,     // 宽度（右边界 - 左边界）
      height: y1 - y0     // 高度（下边界 - 上边界）
    )
  }

  // contentRectPreedit（预编辑内容矩形）：专门用于计算预编辑区域的内容矩形
  // 功能与 contentRect 函数相同，但操作的是预编辑文本视图
  // 参数 range（范围）：预编辑区域中要计算矩形的文本范围
  // 返回值：包含预编辑文本范围的矩形区域
  func contentRectPreedit(range: NSTextRange) -> NSRect {
    // 使用相同的边界值初始化策略
    var x0 = CGFloat.infinity, x1 = -CGFloat.infinity, y0 = CGFloat.infinity, y1 = -CGFloat.infinity
    
    // 枚举预编辑文本视图中的文本段
    preeditTextView.textLayoutManager?.enumerateTextSegments(
      in: range, 
      type: .standard, 
      options: .rangeNotRequired
    ) { _, rect, _, _ in
      var rect = rect  // 创建可变副本进行坐标转换
      
      // 进行预编辑区域特有的坐标转换
      rect.origin.x -= preeditScrollOffset.x    // 减去预编辑区域的水平滚动偏移
      rect.origin.y -= preeditScrollOffset.y    // 减去预编辑区域的垂直滚动偏移
      rect.origin.y += preeditFrameOriginY      // 加上预编辑框架的垂直偏移
      
      // 更新边界值
      x0 = min(rect.minX, x0)
      x1 = max(rect.maxX, x1)
      y0 = min(rect.minY, y0)
      y1 = max(rect.maxY, y1)
      
      return true  // 继续枚举
    }
    
    // 构造并返回预编辑区域的内容矩形
    return NSRect(x: x0, y: y0, width: x1-x0, height: y1-y0)
  }

  // ========== 视图重绘控制函数 ==========
  // 这个函数用于触发视图的重新绘制，当文本内容或布局发生变化时调用
  // swiftlint:disable:next function_parameter_count
  func drawView(candidateRanges: [NSRange], hilightedIndex: Int, preeditRange: NSRange, highlightedPreeditRange: NSRange, canPageUp: Bool, canPageDown: Bool) {
    // ========== 🔍 调试日志：drawView 参数接收 ==========
    print("🎨 [SquirrelView.drawView] 接收绘制参数:")
    print("   📋 候选字数量: \(candidateRanges.count)")
    print("   🎯 高亮索引: \(hilightedIndex)")
    print("   📄 预编辑范围: \(preeditRange)")
    for (i, range) in candidateRanges.enumerated() {
      let isHighlighted = (i == hilightedIndex)
      print("   📝 候选字[\(i)]: \(range) \(isHighlighted ? "🔵 [高亮]" : "")")
    }
    print("   ----------------------------------------")
    
    // 保存新的状态信息
    self.candidateRanges = candidateRanges              // 候选字范围列表
    self.hilightedIndex = hilightedIndex                // 高亮的候选字索引
    self.preeditRange = preeditRange                    // 预编辑文本范围
    self.highlightedPreeditRange = highlightedPreeditRange  // 预编辑文本高亮范围
    self.canPageUp = canPageUp                          // 是否可以向上翻页
    self.canPageDown = canPageDown                      // 是否可以向下翻页
    self.needsDisplay = true                            // 标记需要重新显示
  }

  // 所有绘制操作都在这里进行
  // 这是整个视图的绘制核心，就像画家在画布上作画
  // swiftlint:disable:next cyclomatic_complexity
  override func draw(_ dirtyRect: NSRect) {
    // ========== 🔍 调试日志：draw 函数开始 ==========
    print("🖼️ [SquirrelView.draw] 开始实际绘制:")
    print("   🎯 当前高亮索引: \(hilightedIndex)")
    print("   📋 候选字数量: \(candidateRanges.count)")
    print("   📏 绘制区域: \(dirtyRect)")
    
    // 声明各种路径变量，用于绘制不同的形状
    var backgroundPath: CGPath?              // 背景路径
    var preeditPath: CGPath?                 // 预编辑文本背景路径
    var candidatePaths: CGMutablePath?       // 候选字背景路径
    var highlightedPath: CGMutablePath?      // 高亮候选字路径
    var highlightedPreeditPath: CGMutablePath?  // 高亮预编辑文本路径
    let theme = currentTheme                 // 获取当前主题

    // 🔍 调试：检查翻页按钮相关设置
    print("🔍 [SquirrelView.draw] 翻页设置调试:")
    print("   📊 showPaging: \(theme.showPaging)")
    print("   📏 pagingOffset: \(theme.pagingOffset)")
    print("   📦 原始 dirtyRect: \(dirtyRect)")

    // 计算包含区域，为翻页按钮留出空间
    var containingRect = dirtyRect
    containingRect.size.width -= theme.pagingOffset
    let backgroundRect = containingRect
    
    print("   📦 调整后 containingRect: \(containingRect)")
    print("   📦 backgroundRect: \(backgroundRect)")
    print("   ----------------------------------------")
    if DEBUG_LAYOUT_LOGS {
      print("   🧭 ScrollOffsets preedit=\(preeditScrollOffset) candidate=\(candidateScrollOffset)")
      print("   🧱 Frames preeditSV=\(preeditScrollView.frame) candidateSV=\(candidateScrollView.frame)")
      print("   🧊 Insets preedit=\(preeditTextView.textContainerInset) candidate=\(candidateTextView.textContainerInset)")
    }

    // 绘制预编辑文本矩形区域
  var preeditRect = NSRect.zero
    if preeditRange.length > 0, let preeditTextRange = convertPreedit(range: preeditRange) {
      // 计算预编辑文本的显示区域
      preeditRect = contentRectPreedit(range: preeditTextRange)
      preeditRect.size.width = backgroundRect.size.width  // 宽度占满背景区域
      // 调整高度，包含边距和行间距
  // 预编辑区域高度：文档高度 + 顶部内边距与半行距（去除圆角额外补偿，确保与候选区严丝合缝）
  preeditRect.size.height += theme.edgeInset.height + theme.preeditLinespace / 2
      preeditRect.origin = backgroundRect.origin
      
      // 如果没有候选字，调整预编辑区域的高度
      if candidateRanges.count == 0 {
        preeditRect.size.height += theme.edgeInset.height - theme.preeditLinespace / 2 - theme.hilitedCornerRadius / 2
      }
      
  // === 对齐调试：preedit 容器与内容的上下边界 ===
  let preeditSV = preeditScrollView
  let clip = preeditSV.contentView
  let tv = preeditTextView
  let svFrame = preeditSV.frame
  let clipBounds = clip.bounds
  let clipRectInSelf = clip.convert(clip.bounds, to: self)
  let tvBoundsInSelf = tv.convert(tv.bounds, to: self)
  var docRectInSelf = NSRect.zero
  if let pr = convertPreedit(range: preeditRange) { docRectInSelf = contentRectPreedit(range: pr) }

  // 以 clipView 的底边为“分区缝”（与设备像素对齐），统一作为候选顶部参考
  let clipBottomInSelf = clipRectInSelf.maxY
  let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
  let seamY = (clipBottomInSelf * scale).rounded() / scale
  // 将 seam 反写到 preeditRect.height，确保后续 inner/outerBox 也使用一致的顶部
  preeditRect.size.height = seamY
  // 最终确定候选区的顶部和高度：严格使用 seam 和 candidateScrollView 的高度
  containingRect.origin.y = seamY
  containingRect.size.height = candidateScrollView.frame.size.height
  print("🧩 [Preedit Align] enforce containingRect top=seamY=\(seamY) height=candidateSV.h=\(candidateScrollView.frame.size.height)")
  print("🧩 [Preedit Align] seam(device-aligned)=\(seamY) scale=\(scale)")

  print("🧩 [Preedit Align] sv.frame=\(svFrame) sv.maxY=\(svFrame.maxY)")
  print("🧩 [Preedit Align] clip.bounds=\(clipBounds) clipInSelf=\(clipRectInSelf)")
  print("🧩 [Preedit Align] tv.boundsInSelf=\(tvBoundsInSelf) tv.maxYInSelf=\(tvBoundsInSelf.maxY)")
  print("🧩 [Preedit Align] docRectInSelf=\(docRectInSelf) doc.maxY=\(docRectInSelf.maxY)")
  print("🧩 [Preedit Align] preeditRect=\(preeditRect) preeditRect.maxY=\(preeditRect.maxY)")
  let gapSVvsPreeditRect = svFrame.maxY - preeditRect.maxY
  let gapClipVsPreeditRect = clipRectInSelf.maxY - preeditRect.maxY
  let gapDocVsSV = svFrame.maxY - docRectInSelf.maxY
  print("🧩 [Preedit Align] gap: sv.maxY-preeditRect.maxY=\(gapSVvsPreeditRect), clipInSelf.maxY-preeditRect.maxY=\(gapClipVsPreeditRect), sv.maxY-doc.maxY=\(gapDocVsSV)")
      
      // 如果预编辑文本有背景颜色，创建背景路径
      if theme.preeditBackgroundColor != nil {
        preeditPath = drawSmoothLines(rectVertex(of: preeditRect), straightCorner: Set(), alpha: 0, beta: 0)
      }
    }

  containingRect = carveInset(rect: containingRect)  // 雕刻内边距
  if DEBUG_LAYOUT_LOGS { print("   ✂️ carved containingRect=\(containingRect)") }
    
    // ========== 🔍 调试日志：候选字绘制循环开始 ==========
    print("🎨 [SquirrelView.draw] 开始绘制候选字:")
    print("   📊 包含矩形: \(containingRect)")
    print("   🎯 当前高亮索引: \(hilightedIndex)")
    
    // 绘制候选字矩形区域p
    for i in 0..<candidateRanges.count {
      let candidate = candidateRanges[i]  // 获取当前候选字的范围
      let isHighlighted = (i == hilightedIndex)
      if DEBUG_LAYOUT_LOGS && i == 0 {
        if let tr = convert(range: candidate) {
          let r = contentRect(range: tr)
          print("   🔎 firstCandidate contentRect=\(r)")
        }
      }
      
      // ========== 🔍 调试日志：每个候选字的处理 ==========
      print("   📝 处理候选字[\(i)]:")
      print("      📍 范围: \(candidate)")
      print("      🎯 是否高亮: \(isHighlighted)")
      print("      📏 范围长度: \(candidate.length)")
      
      if i == hilightedIndex {
        // 绘制高亮（选中）的候选字背景
        print("      🔵 [高亮路径] 开始绘制高亮背景...")
        print("      🎨 高亮背景颜色: \(theme.highlightedBackColor?.description ?? "nil")")
        
        if candidate.length > 0 && theme.highlightedBackColor != nil {
          print("      ✅ [高亮路径] 条件满足，调用 drawPathCandidate...")
          highlightedPath = drawPathCandidate(highlightedRange: candidate, backgroundRect: backgroundRect, preeditRect: preeditRect, containingRect: containingRect, extraExpansion: 0)?.mutableCopy()
          if highlightedPath != nil {
            print("      ✅ [高亮路径] 成功创建高亮路径")
          } else {
            print("      ❌ [高亮路径] 创建高亮路径失败")
          }
        } else {
          print("      ❌ [高亮路径] 条件不满足:")
          print("         - 范围长度 > 0: \(candidate.length > 0)")
          print("         - 高亮颜色不为nil: \(theme.highlightedBackColor != nil)")
        }
      } else {
        // 绘制其他候选字的背景
        print("      ⚪ [普通路径] 开始绘制普通背景...")
        print("      🎨 普通背景颜色: \(theme.candidateBackColor?.description ?? "nil")")
        
        if candidate.length > 0 && theme.candidateBackColor != nil {
          print("      ✅ [普通路径] 条件满足，调用 drawPathCandidate...")
          let candidatePath = drawPathCandidate(highlightedRange: candidate, backgroundRect: backgroundRect, preeditRect: preeditRect,
                                       containingRect: containingRect, extraExpansion: theme.surroundingExtraExpansion)
          // 如果候选字路径容器不存在，创建一个
          if candidatePaths == nil {
            candidatePaths = CGMutablePath()
          }
          // 将候选字路径添加到容器中
          if let candidatePath = candidatePath {
            candidatePaths?.addPath(candidatePath)
            print("      ✅ [普通路径] 成功添加普通候选字路径")
          } else {
            print("      ❌ [普通路径] 创建普通候选字路径失败")
          }
        } else {
          print("      ❌ [普通路径] 条件不满足:")
          print("         - 范围长度 > 0: \(candidate.length > 0)")
          print("         - 普通背景颜色不为nil: \(theme.candidateBackColor != nil)")
        }
      }
      print("   ----------------------------------------")
    }
    
    // ========== 🔍 调试日志：候选字绘制循环结束 ==========
    print("🎨 [SquirrelView.draw] 候选字绘制循环结束")
    print("   🔵 高亮路径是否创建: \(highlightedPath != nil)")
    print("   ⚪ 普通路径是否创建: \(candidatePaths != nil)")
    print("   ----------------------------------------")

    // ========== 绘制预编辑文本的高亮部分 ==========
    // 这个代码块负责为用户正在输入的拼音文本绘制高亮背景
    // 高亮效果类似于文本编辑器中选中文本时的背景色
    
    // ========== 第一步：条件检查 ==========
    // 只有满足以下所有条件时才进行高亮绘制：
    // 1. highlightedPreeditRange.length > 0：有需要高亮的文本范围
    // 2. theme.highlightedPreeditColor != nil：主题中定义了高亮颜色
    // 3. convertPreedit 转换成功：能够将范围转换为文本布局系统可用的格式
    if (highlightedPreeditRange.length > 0) && (theme.highlightedPreeditColor != nil), 
       let highlightedPreeditTextRange = convertPreedit(range: highlightedPreeditRange) {
      
      // ========== 第二步：计算内部边界框（innerBox）==========
      // innerBox（内边界框）：高亮背景实际绘制的区域，考虑了内边距
      var innerBox = preeditRect  // 从预编辑矩形开始
      
      // 调整宽度：两边各减去边距和1像素的额外空间
      // edgeInset.width（边缘内边距宽度）：主题定义的左右内边距
      innerBox.size.width -= (theme.edgeInset.width + 1) * 2
      
      // 调整水平位置：向右偏移边距和1像素
      innerBox.origin.x += theme.edgeInset.width + 1
      
      // 调整垂直位置：向下偏移边距和1像素
      innerBox.origin.y += theme.edgeInset.height + 1
      
      // ========== 第三步：根据是否有候选词调整高度 ==========
      if candidateRanges.count == 0 {
        // 情况1：没有候选词时，上下都减去边距（保持上下对称）
        innerBox.size.height -= (theme.edgeInset.height + 1) * 2
      } else {
        // 情况2：有候选词时，仅扣除顶部内边距，让预编辑高亮的底边“贴合 seam”（无缝衔接候选区）
        // 之前这里还额外减去了 preeditLinespace/2 + 2 等，导致底部形成约 7~9 像素的可见缝隙。
        innerBox.size.height -= (theme.edgeInset.height + 1)

        if DEBUG_LAYOUT_LOGS {
          // 记录与 seam 的剩余距离（应接近 0）
          let seam = preeditRect.maxY
          let residual = max(0, seam - (innerBox.origin.y + innerBox.size.height))
          let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
          print("🧵 [Preedit.InnerBox] with candidates: topPadding=\(theme.edgeInset.height + 1), bottomResidualToSeam=\(residual) (scale=\(scale))")
        }
      }
      
      // ========== 第四步：计算外部边界框（outerBox）==========
      // outerBox（外边界框）：用于约束高亮形状的外部限制，考虑了圆角和边框
      var outerBox = preeditRect  // 从预编辑矩形开始
      
      // 调整尺寸：减去圆角半径和边框线宽度的影响
      // borderLineWidth（边框线宽度）：边框的粗细
      // max(0, ...)：确保不会得到负值
      outerBox.size.height -= max(0, theme.hilitedCornerRadius + theme.borderLineWidth)
      outerBox.size.width -= max(0, theme.hilitedCornerRadius + theme.borderLineWidth)
      
      // 调整位置：向右下方偏移一半的圆角和边框尺寸，使边界框居中
      outerBox.origin.x += max(0, theme.hilitedCornerRadius + theme.borderLineWidth) / 2
      outerBox.origin.y += max(0, theme.hilitedCornerRadius + theme.borderLineWidth) / 2

      // ========== 第五步：计算多行文本的矩形分布 ==========
      // multilineRectsPreedit（多行矩形预编辑）：将文本范围分解为多个矩形
      // 返回三个矩形：开头矩形、主体矩形、结尾矩形
      // forRange（文本范围）：要处理的高亮文本范围
      // extraSurounding（额外环绕）：0表示不添加额外的环绕空间
      // bounds（边界）：使用外边界框作为限制
      let (leadingRect, bodyRect, trailingRect) = multilineRectsPreedit(
        forRange: highlightedPreeditTextRange, 
        extraSurounding: 0, 
        bounds: outerBox
      )
      
      // ========== 第六步：将矩形转换为线性点集合 ==========
      // linearMultilineFor（线性多行处理）：将矩形转换为可以绘制平滑线条的点集合
      // 返回两组点和两组角点（用于处理可能的多段高亮）
      // highlightedPoints（高亮点集）：第一组高亮区域的顶点
      // highlightedPoints2（第二组高亮点集）：第二组高亮区域的顶点（如果有的话）
      // rightCorners（右角点）：需要特殊处理的右侧角点
      var (highlightedPoints, highlightedPoints2, rightCorners, rightCorners2) = linearMultilineFor(
        body: bodyRect, 
        leading: leadingRect, 
        trailing: trailingRect
      )

      // ========== 第七步：处理第一组高亮路径 ==========
      // carveInset（雕刻内边距）：创建包含矩形，用于边界检查
      containingRect = carveInset(rect: preeditRect)
      
      // expand（扩展顶点）：将点集合在内外边界之间进行扩展，创建更好的视觉效果
      // vertex（顶点）：要扩展的点集合
      // innerBorder（内边界）：内部限制
      // outerBorder（外边界）：外部限制
      highlightedPoints = expand(vertex: highlightedPoints, innerBorder: innerBox, outerBorder: outerBox)
      
      // removeCorner（移除角点）：移除不需要的角点，优化形状
      rightCorners = removeCorner(
        highlightedPoints: highlightedPoints, 
        rightCorners: rightCorners, 
        containingRect: containingRect
      )
      
      // drawSmoothLines（绘制平滑线条）：创建平滑的高亮路径
      // straightCorner（直角点）：需要保持直角的点
      // alpha、beta：控制曲线平滑度的参数
      // 0.3 * theme.hilitedCornerRadius：较小的平滑参数
      // 1.4 * theme.hilitedCornerRadius：较大的平滑参数
      // mutableCopy()：创建可修改的副本
      highlightedPreeditPath = drawSmoothLines(
        highlightedPoints, 
        straightCorner: rightCorners, 
        alpha: 0.3 * theme.hilitedCornerRadius, 
        beta: 1.4 * theme.hilitedCornerRadius
      )?.mutableCopy()
      
      // ========== 第八步：处理第二组高亮路径（如果存在）==========
      // 当文本跨越多行或有多个分离的高亮区域时，可能存在第二组点
      if highlightedPoints2.count > 0 {
        // 对第二组点执行相同的处理流程
        highlightedPoints2 = expand(vertex: highlightedPoints2, innerBorder: innerBox, outerBorder: outerBox)
        rightCorners2 = removeCorner(
          highlightedPoints: highlightedPoints2, 
          rightCorners: rightCorners2, 
          containingRect: containingRect
        )
        
        // 为第二组点创建平滑路径
        let highlightedPreeditPath2 = drawSmoothLines(
          highlightedPoints2, 
          straightCorner: rightCorners2, 
          alpha: 0.3 * theme.hilitedCornerRadius, 
          beta: 1.4 * theme.hilitedCornerRadius
        )
        
        // 将第二条路径添加到主路径中，形成完整的高亮效果
        if let highlightedPreeditPath2 = highlightedPreeditPath2 {
          highlightedPreeditPath?.addPath(highlightedPreeditPath2)
        }
      }
    }

    // 开始绘制背景图形
    NSBezierPath.defaultLineWidth = 0  // 设置默认线宽为0，就像用极细的笔画
    // 创建一个带圆角的背景路径，就像画一个圆角矩形框架
    backgroundPath = drawSmoothLines(rectVertex(of: backgroundRect), straightCorner: Set(), alpha: 0.3 * theme.cornerRadius, beta: 1.4 * theme.cornerRadius)

  // 清空现有的图层，重新开始绘制
  self.layer?.sublayers = nil
    
    // ========== 🔍 调试日志：最终图层处理 ==========
    print("🖼️ [SquirrelView.draw] 开始最终图层处理:")
    print("   🔵 高亮路径: \(highlightedPath != nil ? "存在" : "不存在")")
    print("   ⚪ 普通路径: \(candidatePaths != nil ? "存在" : "不存在")")
    print("   🎨 主题互斥模式: \(theme.mutualExclusive)")
    
    // 创建主背景路径的副本，用于合并所有图形元素
    let backPath = backgroundPath?.mutableCopy()
    // 如果有输入预览区域，将其路径合并到主背景中
    if let path = preeditPath {
      backPath?.addPath(path)
    }
    // 如果设置了互斥模式（高亮区域不重叠）
    if theme.mutualExclusive {
      // 将高亮路径合并到主背景
      if let path = highlightedPath {
        backPath?.addPath(path)
        print("   ✅ 互斥模式：高亮路径已合并到主背景")
      }
      // 将候选字路径合并到主背景
      if let path = candidatePaths {
        backPath?.addPath(path)
        print("   ✅ 互斥模式：候选字路径已合并到主背景")
      }
    }
    
    // 创建主面板图层，设置背景色，就像给画布涂上底色
    let panelLayer = shapeFromPath(path: backPath)
    panelLayer.fillColor = theme.backgroundColor.cgColor
    print("   🎨 主面板图层已创建，背景色: \(theme.backgroundColor)")
    
    // 创建遮罩层，限制绘制范围在背景路径内，就像用模板控制绘画区域
    let panelLayerMask = shapeFromPath(path: backgroundPath)
    panelLayer.mask = panelLayerMask
    
    // 将主图层添加到视图中
    self.layer?.addSublayer(panelLayer)
    print("   ✅ 主面板图层已添加到视图")

    // ====== 几何核查（定位“整体比外框高 ~1px”）======
    if DEBUG_LAYOUT_LOGS {
      let bgBBox = backgroundPath?.boundingBox ?? .zero
      let preeditPlusCand = preeditRect.height + candidateScrollView.frame.height
      print("🔎 [Audit] theme borderWidth=\(theme.borderWidth) borderHeight=\(theme.borderHeight) borderLineWidth=\(theme.borderLineWidth) corner=\(theme.cornerRadius) hilitedCorner=\(theme.hilitedCornerRadius)")
      print("🔎 [Audit] dirtyRect.h=\(dirtyRect.height) backgroundRect.h=\(backgroundRect.height) bgPathBBox.h=\(bgBBox.height) preedit.h=\(preeditRect.height) candSV.h=\(candidateScrollView.frame.height) sum=\(preeditPlusCand)")
      let heightDelta = backgroundRect.height - preeditPlusCand
      print("🔎 [Audit] heightDelta(background - (preedit+cand))=\(heightDelta)")
    }

    // ========== 🔍 调试日志：开始颜色填充 ==========
    print("🎨 [SquirrelView.draw] 开始颜色填充:")
    
    // 开始填充各种颜色和效果
    // 绘制输入预览区域的背景色
    if let color = theme.preeditBackgroundColor, let path = preeditPath {
      print("   📝 预编辑背景色: \(color)")
      let layer = shapeFromPath(path: path)  // 创建预览区图层
      layer.fillColor = color.cgColor  // 设置预览区背景色
      // 创建遮罩路径，控制绘制范围
      let maskPath = backgroundPath?.mutableCopy()
      // 如果是互斥模式且有高亮预览区，将其加入遮罩
      if theme.mutualExclusive, let hilitedPath = highlightedPreeditPath {
        maskPath?.addPath(hilitedPath)
      }
      let mask = shapeFromPath(path: maskPath)  // 创建遮罩
      layer.mask = mask  // 应用遮罩
      panelLayer.addSublayer(layer)  // 添加到主图层
    }
    // 绘制边框线条
    // 绘制边框线条
    if theme.borderLineWidth > 0, let color = theme.borderColor {
      let borderLayer = shapeFromPath(path: backgroundPath)  // 创建边框图层
      borderLayer.lineWidth = theme.borderLineWidth * 2  // 设置边框线宽
      borderLayer.strokeColor = color.cgColor  // 设置边框颜色
      borderLayer.fillColor = nil  // 不填充，只绘制线条
      panelLayer.addSublayer(borderLayer)  // 添加边框图层
    }
    // 绘制高亮的输入预览区域（用户正在输入的文字背景）
    if let color = theme.highlightedPreeditColor, let path = highlightedPreeditPath {
      let layer = shapeFromPath(path: path)  // 创建高亮预览图层
      layer.fillColor = color.cgColor  // 设置高亮颜色
      panelLayer.addSublayer(layer)  // 添加到主图层
    }
    // 绘制候选字的背景色（除了被选中的那个）
    if let color = theme.candidateBackColor, let path = candidatePaths {
      print("   ⚪ 添加候选字背景色: \(color)")
      let layer = shapeFromPath(path: path)  // 创建候选字背景图层
      layer.fillColor = color.cgColor  // 设置候选字背景色
      panelLayer.addSublayer(layer)  // 添加到主图层
      print("   ✅ 候选字背景图层已添加")
    } else {
      print("   ❌ 候选字背景未添加:")
      print("      - 颜色: \(theme.candidateBackColor?.description ?? "nil")")
      print("      - 路径: \(candidatePaths != nil ? "存在" : "不存在")")
    }
    
    // ========== 🔍 关键调试：被选中候选字的高亮背景 ==========
    print("🔵 [关键] 处理高亮候选字背景:")
    print("   🎨 高亮颜色: \(theme.highlightedBackColor?.description ?? "nil")")
    print("   🛤️ 高亮路径: \(highlightedPath != nil ? "存在" : "不存在")")
    
    // 绘制被选中候选字的高亮背景（最重要的视觉反馈）
    if let color = theme.highlightedBackColor, let path = highlightedPath {
      print("   ✅ [关键] 条件满足，开始创建高亮图层...")
      let layer = shapeFromPath(path: path)  // 创建高亮图层
      layer.fillColor = color.cgColor  // 设置高亮背景色
      print("   🎨 高亮图层已创建，颜色: \(color)")
      
      // 如果设置了阴影效果，添加阴影让高亮更突出
      if theme.shadowSize > 0 {
        print("   🌫️ 添加阴影效果，大小: \(theme.shadowSize)")
        let shadowLayer = CAShapeLayer()  // 创建阴影图层
        shadowLayer.shadowColor = NSColor.black.cgColor  // 阴影颜色为黑色
        // 设置阴影偏移量，垂直布局和水平布局方向不同
        shadowLayer.shadowOffset = NSSize(width: theme.shadowSize/2, height: (theme.vertical ? -1 : 1) * theme.shadowSize/2)
        shadowLayer.shadowPath = highlightedPath  // 设置阴影路径
        shadowLayer.shadowRadius = theme.shadowSize  // 设置阴影模糊半径
        shadowLayer.shadowOpacity = 0.2  // 设置阴影透明度
        // 创建复合路径用于阴影遮罩
        let outerPath = backgroundPath?.mutableCopy()
        outerPath?.addPath(path)
        let shadowLayerMask = shapeFromPath(path: outerPath)
        shadowLayer.mask = shadowLayerMask  // 应用阴影遮罩
        // 给高亮区域添加细微的边框线
        layer.strokeColor = NSColor.black.withAlphaComponent(0.15).cgColor
        layer.lineWidth = 0.5
        layer.addSublayer(shadowLayer)  // 将阴影添加到高亮图层
        print("   ✅ 阴影图层已添加")
      } else {
        print("   ⏭️ 跳过阴影：shadowSize = \(theme.shadowSize)")
      }
      
      panelLayer.addSublayer(layer)  // 添加高亮图层到主图层
      print("   ✅ [关键] 高亮图层已成功添加到主图层！")
    } else {
      print("   ❌ [关键] 高亮图层未添加:")
      print("      - 高亮颜色: \(theme.highlightedBackColor?.description ?? "nil")")
      print("      - 高亮路径: \(highlightedPath != nil ? "存在" : "不存在")")
    }
    
    // ========== 🔍 调试日志：绘制完成总结 ==========
    print("🏁 [SquirrelView.draw] 绘制过程完成")
    print("   📊 最终状态总结:")
    print("   🔵 高亮索引: \(hilightedIndex)")
    print("   🎨 高亮颜色设置: \(theme.highlightedBackColor?.description ?? "nil")")
    print("   🛤️ 高亮路径创建: \(highlightedPath != nil ? "成功" : "失败")")
    print("   🖼️ 图层数量: \(panelLayer.sublayers?.count ?? 0)")
    print("   ========================================")
    
    // 设置面板图层的位移偏移，用于翻页效果
    panelLayer.setAffineTransform(CGAffineTransform(translationX: theme.pagingOffset, y: 0))
    // 创建面板路径用于后续处理
    let panelPath = CGMutablePath()
    // 将背景路径添加到面板路径中，并进行坐标变换（翻转Y轴并调整位置）
    panelPath.addPath(backgroundPath!, transform: panelLayer.affineTransform().scaledBy(x: 1, y: -1).translatedBy(x: 0, y: -dirtyRect.height))

    // 创建翻页控制图层（上一页/下一页按钮区域）
    let (pagingLayer, downPath, upPath) = pagingLayer(theme: theme, preeditRect: preeditRect)
    // 如果翻页图层有内容，将其添加到主视图
    if let sublayers = pagingLayer.sublayers, !sublayers.isEmpty {
      self.layer?.addSublayer(pagingLayer)
    }
    // 创建坐标翻转变换，用于适配不同的坐标系统
    let flipTransform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -dirtyRect.height)
    // 处理"下一页"按钮区域
    if let downPath {
      panelPath.addPath(downPath, transform: flipTransform)  // 将下一页路径添加到面板路径
      self.downPath = downPath.copy()  // 保存下一页路径供点击检测使用
    }
    // 处理"上一页"按钮区域
    if let upPath {
      panelPath.addPath(upPath, transform: flipTransform)  // 将上一页路径添加到面板路径
      self.upPath = upPath.copy()  // 保存上一页路径供点击检测使用
    }

  // 将所有路径设置到形状图层中，完成最终的界面绘制
  shape.path = panelPath
  if DEBUG_LAYOUT_LOGS {
    print("🔎 [Audit] shape.path bbox=\(shape.path?.boundingBox ?? .zero)")
  }
  }

  // 点击检测函数：判断用户点击了哪个区域（候选字、翻页按钮等）
  func click(at clickPoint: NSPoint) -> (Int?, Int?, Bool?) {
    var index = 0  // 文本索引位置
    var candidateIndex: Int?  // 被点击的候选字索引
    var preeditIndex: Int?    // 被点击的预编辑文本索引
    
    // 检查是否点击了"下一页"按钮
    if let downPath = self.downPath, downPath.contains(clickPoint) {
      return (nil, nil, false)  // 返回下一页标志
    }
    // 检查是否点击了"上一页"按钮
    if let upPath = self.upPath, upPath.contains(clickPoint) {
      return (nil, nil, true)   // 返回上一页标志
    }
    
    // 检查是否点击在候选窗口内部
    if let path = shape.path, path.contains(clickPoint) {
      let theme = currentTheme
      // 优先判定预编辑区域
      if preeditScrollView.frame.contains(clickPoint), let tlm = preeditTextView.textLayoutManager {
        var point = NSPoint(x: clickPoint.x - preeditScrollView.frame.origin.x - preeditTextView.textContainerInset.width,
                            y: clickPoint.y - preeditScrollView.frame.origin.y - preeditTextView.textContainerInset.height)
        point.x += preeditScrollOffset.x
        point.y += preeditScrollOffset.y
        if let fragment = tlm.textLayoutFragment(for: point) {
          var local = NSPoint(x: point.x - fragment.layoutFragmentFrame.minX,
                              y: point.y - fragment.layoutFragmentFrame.minY)
          index = tlm.offset(from: tlm.documentRange.location, to: fragment.rangeInElement.location)
          for lineFragment in fragment.textLineFragments where lineFragment.typographicBounds.contains(local) {
            local = NSPoint(x: local.x - lineFragment.typographicBounds.minX,
                            y: local.y - lineFragment.typographicBounds.minY)
            index += lineFragment.characterIndex(for: local)
            if index >= preeditRange.location && index < preeditRange.upperBound {
              preeditIndex = index
            }
            break
          }
        }
      } else if candidateScrollView.frame.contains(clickPoint), let tlm = candidateTextView.textLayoutManager {
        // 先进行一次与绘制几何一致的命中测试，避免段前/段后间距把点归属到相邻行导致 off-by-one
        let halfLinespace = currentTheme.linespace / 2
        // 与绘制时一致：用 preedit clipView 的底边作为 seam，并进行设备像素对齐
        let clip = preeditScrollView.contentView
        let clipRectInSelf = clip.convert(clip.bounds, to: self)
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let seamTop = (clipRectInSelf.maxY * scale).rounded() / scale
        let svX = candidateScrollView.frame.origin.x
        let svW = candidateScrollView.frame.width
        // 仅当点在候选滚动区域的水平范围内时才测试
        if clickPoint.x >= svX && clickPoint.x <= svX + svW {
          for i in 0..<candidateRanges.count {
            if let tr = convert(range: candidateRanges[i]) {
              var r = contentRect(range: tr) // 已在 self 坐标系，含 frame.origin.y 与 scrollOffset 修正
              // 将矩形扩展为与高亮绘制一致的高度与顶部偏移：+linespace 高度，-halfLinespace 顶部
              r.size.height += currentTheme.linespace
              r.origin.y = r.origin.y + seamTop - halfLinespace
              // 宽度用候选滚动区域，确保命中判定覆盖整行
              r.origin.x = svX
              r.size.width = svW
              if r.contains(clickPoint) {
                candidateIndex = i
                break
              }
            }
          }
        }
        // 若几何命中未命中，则回退到文本系统的精确映射
        if candidateIndex == nil {
          var point = NSPoint(x: clickPoint.x - candidateScrollView.frame.origin.x - candidateTextView.textContainerInset.width,
                              y: clickPoint.y - candidateScrollView.frame.origin.y - candidateTextView.textContainerInset.height)
          point.x += candidateScrollOffset.x
          point.y += candidateScrollOffset.y
          if let fragment = tlm.textLayoutFragment(for: point) {
            var local = NSPoint(x: point.x - fragment.layoutFragmentFrame.minX,
                                y: point.y - fragment.layoutFragmentFrame.minY)
            index = tlm.offset(from: tlm.documentRange.location, to: fragment.rangeInElement.location)
            for lineFragment in fragment.textLineFragments where lineFragment.typographicBounds.contains(local) {
              local = NSPoint(x: local.x - lineFragment.typographicBounds.minX,
                              y: local.y - lineFragment.typographicBounds.minY)
              index += lineFragment.characterIndex(for: local)
              for i in 0..<candidateRanges.count {
                let range = candidateRanges[i]
                if index >= range.location && index < range.upperBound {
                  candidateIndex = i
                  break
                }
              }
              break
            }
          }
        }
      }
    }
    // 返回点击结果：(候选字索引, 预编辑文本索引, 翻页方向)
    return (candidateIndex, preeditIndex, nil)
  }
}

// 私有扩展：包含绘图相关的辅助函数
private extension SquirrelView {
  // 调整后的符号函数，当尺寸较小时减小圆角半径，避免过度圆角
  func sign(_ number: NSPoint) -> NSPoint {
    if number.length >= 2 {
      return number / number.length  // 标准化向量，保持方向但长度为1
    } else {
      return number / 2  // 小向量时减半，产生更平缓的效果
    }
  }

  // 贝塞尔三次曲线绘制函数，创建连续圆滑的线条
  // vertex: 顶点数组，straightCorner: 需要保持直角的顶点，alpha/beta: 控制曲线圆滑度的参数
  func drawSmoothLines(_ vertex: [NSPoint], straightCorner: Set<Int>, alpha: CGFloat, beta rawBeta: CGFloat) -> CGPath? {
    // 至少需要3个顶点才能形成有效的图形
    guard vertex.count >= 3 else {
      return nil
    }
    // 确保beta值不为零，避免除零错误
    let beta = max(0.00001, rawBeta)
    let path = CGMutablePath()  // 创建可变路径对象
    
    // 初始化关键点：前一个点、当前点、下一个点
    var previousPoint = vertex[vertex.count-1]  // 最后一个顶点作为起始的前一个点
    var point = vertex[0]  // 第一个顶点
    var nextPoint: NSPoint
    var control1: NSPoint   // 贝塞尔曲线控制点1
    var control2: NSPoint   // 贝塞尔曲线控制点2
    var target = previousPoint  // 目标点
    var diff = point - previousPoint  // 向量差
    
    // 如果最后一个顶点不需要保持直角，则应用圆角效果
    if straightCorner.isEmpty || !straightCorner.contains(vertex.count-1) {
      target += sign(diff / beta) * beta  // 调整起始点位置以创建圆角
    }
    path.move(to: target)  // 将路径起点移动到目标位置
    
    // 遍历所有顶点，为每个顶点创建平滑连接
    for i in 0..<vertex.count {
      // 获取当前处理的三个相邻顶点
      previousPoint = vertex[(vertex.count+i-1)%vertex.count]  // 前一个顶点（循环获取）
      point = vertex[i]  // 当前顶点
      nextPoint = vertex[(i+1)%vertex.count]  // 下一个顶点（循环获取）
      target = point  // 设置目标为当前顶点
      
      // 如果当前顶点需要保持直角
      if straightCorner.contains(i) {
        path.addLine(to: target)  // 直接画直线到目标点
      } else {
        // 创建圆滑的曲线连接
        control1 = point  // 初始化第一个控制点
        diff = point - previousPoint  // 计算从前一点到当前点的向量
        
        // 调整目标点和控制点以创建圆角效果
        target -= sign(diff / beta) * beta  // 向内缩进目标点
        control1 -= sign(diff / beta) * alpha  // 调整控制点1位置
        
        path.addLine(to: target)  // 画线到调整后的目标点
        target = point  // 重置目标为当前顶点
        control2 = point  // 初始化第二个控制点
        diff = nextPoint - point  // 计算从当前点到下一点的向量
        
        // 为下一段曲线准备目标点和控制点
        target += sign(diff / beta) * beta  // 向外延伸目标点
        control2 += sign(diff / beta) * alpha  // 调整控制点2位置

        // 绘制贝塞尔三次曲线，创建平滑的圆角过渡
        path.addCurve(to: target, control1: control1, control2: control2)
      }
    }
    path.closeSubpath()  // 闭合路径，形成完整的封闭图形
    return path  // 返回完成的路径
  }

  // 获取矩形的四个顶点坐标，按逆时针顺序排列
  func rectVertex(of rect: NSRect) -> [NSPoint] {
    [rect.origin,  // 左下角
     NSPoint(x: rect.origin.x, y: rect.origin.y+rect.size.height),  // 左上角
     NSPoint(x: rect.origin.x+rect.size.width, y: rect.origin.y+rect.size.height),  // 右上角
     NSPoint(x: rect.origin.x+rect.size.width, y: rect.origin.y)]  // 右下角
  }

  // 判断矩形是否接近空（面积很小），用于优化绘制性能
  func nearEmpty(_ rect: NSRect) -> Bool {
    return rect.size.height * rect.size.width < 1  // 面积小于1认为是空矩形
  }

  // 计算包含指定文本范围的3个矩形区域
  // leadingRect: 首行不完整部分，trailingRect: 末行不完整部分，bodyRect: 中间的完整行部分
  func multilineRects(forRange range: NSTextRange, extraSurounding: Double, bounds: NSRect) -> (NSRect, NSRect, NSRect) {
    let edgeInset = currentTheme.edgeInset  // 获取边距设置
    var lineRects = [NSRect]()  // 存储所有行的矩形
    
    // 遍历文本范围内的所有文本段，收集每行的矩形区域
    textLayoutManager.enumerateTextSegments(in: range, type: .standard, options: [.rangeNotRequired]) { _, rect, _, _ in
      var newRect = rect
      // 文档坐标 -> 可见坐标（扣除滚动偏移）
      newRect.origin.x -= scrollOffset.x  // 扣除水平滚动偏移量，转换为视图坐标系
      newRect.origin.y -= scrollOffset.y  // 扣除垂直滚动偏移量，转换为视图坐标系
      newRect.origin.x += edgeInset.width  // 应用水平边距，给文字留出内边距
      newRect.origin.y += edgeInset.height  // 应用垂直边距，给文字留出内边距
      newRect.size.height += currentTheme.linespace  // 增加行间距，让文字行之间有合适的空隙
      newRect.origin.y -= currentTheme.linespace / 2  // 调整垂直位置以居中行间距，保持对称
      lineRects.append(newRect)  // 将处理后的矩形添加到数组，用于后续计算
      return true  // 继续遍历下一个文本段
    }

    // 根据行数分配三个区域，这样做是为了处理多行高亮的复杂情况
    // 比如用户选择了跨越多行的文本，需要分别处理不完整的首尾行和完整的中间行
    var leadingRect = NSRect.zero    // 首行不完整区域（第一行可能只选中了一部分）
    var bodyRect = NSRect.zero       // 中间完整行区域（完整选中的行，占满整行宽度）
    var trailingRect = NSRect.zero   // 末行不完整区域（最后一行可能只选中了一部分）
    
    if lineRects.count == 1 {
      // 只有一行：全部作为主体区域，最简单的情况
      bodyRect = lineRects[0]
    } else if lineRects.count == 2 {
      // 两行：分别作为首行和末行，中间没有完整行
      leadingRect = lineRects[0]
      trailingRect = lineRects[1]
    } else if lineRects.count > 2 {
      // 多行：首行、中间行、末行分别处理，这是最复杂的情况
      leadingRect = lineRects[0]  // 第一行（部分选中）
      trailingRect = lineRects[lineRects.count-1]  // 最后一行（部分选中）
      
      // 计算中间所有行的边界框，这些行是完全选中的
      // 使用边界计算法找出包含所有中间行的最小矩形
      // swiftlint:disable:next identifier_name
      var x0 = CGFloat.infinity, x1 = -CGFloat.infinity, y0 = CGFloat.infinity, y1 = -CGFloat.infinity
      for i in 1..<(lineRects.count-1) {  // 跳过首行和末行，只处理中间行
        let rect = lineRects[i]
        x0 = min(rect.minX, x0)  // 找到最左边的位置
        x1 = max(rect.maxX, x1)  // 找到最右边的位置
        y0 = min(rect.minY, y0)  // 找到最下边的位置
        y1 = max(rect.maxY, y1)  // 找到最上边的位置
      }
      // 确保中间区域与首末行正确连接，避免出现间隙
      y0 = min(leadingRect.maxY, y0)  // 中间区域的上边界不能超过首行的下边界
      y1 = max(trailingRect.minY, y1)  // 中间区域的下边界不能低于末行的上边界
      bodyRect = NSRect(x: x0, y: y0, width: x1-x0, height: y1-y0)  // 构建中间区域矩形
    }

    // 如果需要额外的周围间距（让高亮区域更明显）
    if extraSurounding > 0 {
      if nearEmpty(leadingRect) && nearEmpty(trailingRect) {
        // 只有主体区域时，扩展其宽度，让高亮区域在候选字周围有更多空间
        bodyRect = expandHighlightWidth(rect: bodyRect, extraSurrounding: extraSurounding)
      } else {
        // 分别为首行和末行扩展宽度，确保每个区域都有合适的间距
        if !(nearEmpty(leadingRect)) {
          leadingRect = expandHighlightWidth(rect: leadingRect, extraSurrounding: extraSurounding)
        }
        if !(nearEmpty(trailingRect)) {
          trailingRect = expandHighlightWidth(rect: trailingRect, extraSurrounding: extraSurounding)
        }
      }
    }

    // 调整多行文本的矩形以确保正确的布局对齐
    // 这是为了让多行选择看起来是一个连贯的区域，而不是分离的矩形
    if !nearEmpty(leadingRect) && !nearEmpty(trailingRect) {
      // 首行延伸到右边界，因为用户选择从某个位置开始到行尾
      leadingRect.size.width = bounds.maxX - leadingRect.origin.x
      // 末行从左边界开始，因为用户选择从行首到某个位置结束
      trailingRect.size.width = trailingRect.maxX - bounds.minX
      trailingRect.origin.x = bounds.minX
      
      if !nearEmpty(bodyRect) {
        // 中间区域占满整个宽度，因为这些行是完全选中的
        bodyRect.size.width = bounds.size.width
        bodyRect.origin.x = bounds.origin.x
      } else {
        // 如果没有中间区域（只有两行），调整首末行的连接
        let diff = trailingRect.minY - leadingRect.maxY  // 计算首末行之间的间隙
        leadingRect.size.height += diff / 2    // 首行向下延伸一半间隙，连接到中间
        trailingRect.size.height += diff / 2   // 末行向上延伸一半间隙，连接到中间
        trailingRect.origin.y -= diff / 2      // 调整末行位置，确保连接自然
      }
    }

    return (leadingRect, bodyRect, trailingRect)  // 返回三个区域
  }

  // 预编辑区域的多行矩形计算，使用预编辑文本系统与其滚动偏移
  func multilineRectsPreedit(forRange range: NSTextRange, extraSurounding: Double, bounds: NSRect) -> (NSRect, NSRect, NSRect) {
    let edgeInset = currentTheme.edgeInset
    var lineRects = [NSRect]()
    preeditTextView.textLayoutManager?.enumerateTextSegments(in: range, type: .standard, options: [.rangeNotRequired]) { _, rect, _, _ in
      var newRect = rect
      newRect.origin.x -= preeditScrollOffset.x
      newRect.origin.y -= preeditScrollOffset.y
      newRect.origin.x += edgeInset.width
      newRect.origin.y += edgeInset.height
      newRect.size.height += currentTheme.preeditLinespace
      newRect.origin.y -= currentTheme.preeditLinespace / 2
      lineRects.append(newRect)
      return true
    }

    var leadingRect = NSRect.zero
    var bodyRect = NSRect.zero
    var trailingRect = NSRect.zero
    if lineRects.count == 1 {
      bodyRect = lineRects[0]
    } else if lineRects.count == 2 {
      leadingRect = lineRects[0]
      trailingRect = lineRects[1]
    } else if lineRects.count > 2 {
      leadingRect = lineRects[0]
      trailingRect = lineRects[lineRects.count-1]
      var x0 = CGFloat.infinity, x1 = -CGFloat.infinity, y0 = CGFloat.infinity, y1 = -CGFloat.infinity
      for i in 1..<(lineRects.count-1) {
        let rect = lineRects[i]
        x0 = min(rect.minX, x0)
        x1 = max(rect.maxX, x1)
        y0 = min(rect.minY, y0)
        y1 = max(rect.maxY, y1)
      }
      y0 = min(leadingRect.maxY, y0)
      y1 = max(trailingRect.minY, y1)
      bodyRect = NSRect(x: x0, y: y0, width: x1-x0, height: y1-y0)
    }

    if extraSurounding > 0 {
      if nearEmpty(leadingRect) && nearEmpty(trailingRect) {
        bodyRect = expandHighlightWidth(rect: bodyRect, extraSurrounding: extraSurounding)
      } else {
        if !(nearEmpty(leadingRect)) {
          leadingRect = expandHighlightWidth(rect: leadingRect, extraSurrounding: extraSurounding)
        }
        if !(nearEmpty(trailingRect)) {
          trailingRect = expandHighlightWidth(rect: trailingRect, extraSurrounding: extraSurounding)
        }
      }
    }

    if !nearEmpty(leadingRect) && !nearEmpty(trailingRect) {
      leadingRect.size.width = bounds.maxX - leadingRect.origin.x
      trailingRect.size.width = trailingRect.maxX - bounds.minX
      trailingRect.origin.x = bounds.minX
      if !nearEmpty(bodyRect) {
        bodyRect.size.width = bounds.size.width
        bodyRect.origin.x = bounds.origin.x
      } else {
        let diff = trailingRect.minY - leadingRect.maxY
        leadingRect.size.height += diff / 2
        trailingRect.size.height += diff / 2
        trailingRect.origin.y -= diff / 2
      }
    }
    return (leadingRect, bodyRect, trailingRect)
  }

  // 根据multilineRectForRange得到的3个矩形，计算包含指定文本范围的多边形顶点
  // 这个函数的作用是将矩形区域转换为多边形顶点，以便绘制复杂的多行高亮形状
  // 不同的矩形组合会产生不同形状的多边形，比如L形、矩形、或者复杂的连接形状
  func multilineVertex(leadingRect: NSRect, bodyRect: NSRect, trailingRect: NSRect) -> [NSPoint] {
    // 根据不同的矩形组合情况，返回相应的多边形顶点
    if nearEmpty(bodyRect) && !nearEmpty(leadingRect) && nearEmpty(trailingRect) {
      // 只有首行：返回首行矩形的顶点，这是最简单的情况
      return rectVertex(of: leadingRect)
    } else if nearEmpty(bodyRect) && nearEmpty(leadingRect) && !nearEmpty(trailingRect) {
      // 只有末行：返回末行矩形的顶点，也是简单的矩形情况
      return rectVertex(of: trailingRect)
    } else if nearEmpty(leadingRect) && nearEmpty(trailingRect) && !nearEmpty(bodyRect) {
      // 只有主体：返回主体矩形的顶点，单行或者整行选择的情况
      return rectVertex(of: bodyRect)
    } else if nearEmpty(trailingRect) && !nearEmpty(bodyRect) {
      // 有首行和主体，无末行：连接首行和主体区域，形成L形或者T形
      let leadingVertex = rectVertex(of: leadingRect)
      let bodyVertex = rectVertex(of: bodyRect)
      // 按特定顺序连接两个矩形的顶点，形成一个连贯的多边形
      return [bodyVertex[0], bodyVertex[1], bodyVertex[2], leadingVertex[3], leadingVertex[0], leadingVertex[1]]
    } else if nearEmpty(leadingRect) && !nearEmpty(bodyRect) {
      // 有末行和主体，无首行：连接主体和末行区域，形成另一种L形
      let trailingVertex = rectVertex(of: trailingRect)
      let bodyVertex = rectVertex(of: bodyRect)
      // 按顺序连接，确保多边形的连续性
      return [trailingVertex[1], trailingVertex[2], trailingVertex[3], bodyVertex[2], bodyVertex[3], bodyVertex[0]]
    } else if !nearEmpty(leadingRect) && !nearEmpty(trailingRect) && nearEmpty(bodyRect) && (leadingRect.maxX>trailingRect.minX) {
      // 只有首行和末行，且有重叠：创建连接的多边形，处理跨行但没有完整中间行的情况
      let leadingVertex = rectVertex(of: leadingRect)
      let trailingVertex = rectVertex(of: trailingRect)
      // 创建一个复杂的八边形，连接两个不相邻的矩形
      return [trailingVertex[0], trailingVertex[1], trailingVertex[2], trailingVertex[3], leadingVertex[2], leadingVertex[3], leadingVertex[0], leadingVertex[1]]
    } else if !nearEmpty(leadingRect) && !nearEmpty(trailingRect) && !nearEmpty(bodyRect) {
      // 三个区域都存在：创建完整的多行多边形，这是最复杂的情况
      let leadingVertex = rectVertex(of: leadingRect)
      let bodyVertex = rectVertex(of: bodyRect)
      let trailingVertex = rectVertex(of: trailingRect)
      // 创建一个连接三个区域的复杂多边形，确保所有区域都平滑连接
      return [trailingVertex[1], trailingVertex[2], trailingVertex[3], bodyVertex[2], leadingVertex[3], leadingVertex[0], leadingVertex[1], bodyVertex[0]]
    } else {
      // 其他情况：返回空数组，表示没有有效的多边形可以绘制
      return [NSPoint]()
    }
  }

  // 将顶点扩展到外边界：如果顶点在内边界外，将其扩展到外边界
  // 这个函数用于确保高亮区域不会超出允许的边界范围
  // 就像给绘制区域加上一个"栅栏"，顶点不能越过这个边界
  func expand(vertex: [NSPoint], innerBorder: NSRect, outerBorder: NSRect) -> [NSPoint] {
    var newVertex = [NSPoint]()
    for i in 0..<vertex.count {
      var point = vertex[i]
      // 检查和调整水平方向的边界
      if point.x < innerBorder.origin.x {
        // 如果点在内边界左侧，移动到外边界左侧
        point.x = outerBorder.origin.x
      } else if point.x > innerBorder.origin.x+innerBorder.size.width {
        // 如果点在内边界右侧，移动到外边界右侧
        point.x = outerBorder.origin.x+outerBorder.size.width
      }
      // 检查和调整垂直方向的边界
      if point.y < innerBorder.origin.y {
        // 如果点在内边界下方，移动到外边界下方
        point.y = outerBorder.origin.y
      } else if point.y > innerBorder.origin.y+innerBorder.size.height {
        // 如果点在内边界上方，移动到外边界上方
        point.y = outerBorder.origin.y+outerBorder.size.height
      }
      newVertex.append(point)  // 将调整后的点加入新的顶点数组
    }
    return newVertex  // 返回边界调整后的顶点数组
  }

  // 根据向量差值计算方向向量，用于确定边缘扩展的方向
  // 这个函数将任意方向简化为4个基本方向：上、下、左、右
  func direction(diff: CGPoint) -> CGPoint {
    if diff.y == 0 && diff.x > 0 {
      return NSPoint(x: 0, y: 1)    // 向右移动 -> 向上扩展
    } else if diff.y == 0 && diff.x < 0 {
      return NSPoint(x: 0, y: -1)   // 向左移动 -> 向下扩展
    } else if diff.x == 0 && diff.y > 0 {
      return NSPoint(x: -1, y: 0)   // 向上移动 -> 向左扩展
    } else if diff.x == 0 && diff.y < 0 {
      return NSPoint(x: 1, y: 0)    // 向下移动 -> 向右扩展
    } else {
      return NSPoint(x: 0, y: 0)    // 斜向或无移动 -> 不扩展
    }
  }

  // 从CGPath创建CAShapeLayer的便捷函数
  // CAShapeLayer是Core Animation中用于绘制形状的图层类
  func shapeFromPath(path: CGPath?) -> CAShapeLayer {
    let layer = CAShapeLayer()        // 创建新的形状图层
    layer.path = path                 // 设置图层的路径
    layer.fillRule = .evenOdd         // 设置填充规则为奇偶规则，处理复杂形状的内外判断
    return layer                      // 返回配置好的图层
  }

  // 顺时针扩展多边形顶点，用于创建加粗的边框效果
  // 这个函数假设顶点是按顺时针方向排列的，通过向外扩展每个顶点来增大多边形
  // Assumes clockwise iteration
  func enlarge(vertex: [NSPoint], by: Double) -> [NSPoint] {
    if by != 0 {  // 只有在扩展值不为零时才进行处理
      var previousPoint: NSPoint    // 前一个顶点
      var point: NSPoint           // 当前顶点
      var nextPoint: NSPoint       // 下一个顶点
      var results = vertex         // 复制原始顶点数组作为结果
      var newPoint: NSPoint        // 计算出的新顶点位置
      var displacement: NSPoint    // 位移向量
      
      // 遍历每个顶点，计算其扩展后的新位置
      for i in 0..<vertex.count {
        // 获取当前顶点的前后邻居（循环索引）
        previousPoint = vertex[(vertex.count+i-1) % vertex.count]
        point = vertex[i]
        nextPoint = vertex[(i+1) % vertex.count]
        newPoint = point  // 从当前点开始计算
        
        // 根据从前一点到当前点的方向进行扩展
        displacement = direction(diff: point - previousPoint)
        newPoint.x += by * displacement.x  // 在x方向扩展
        newPoint.y += by * displacement.y  // 在y方向扩展
        
        // 根据从当前点到下一点的方向进行扩展
        displacement = direction(diff: nextPoint - point)
        newPoint.x += by * displacement.x  // 在x方向继续扩展
        newPoint.y += by * displacement.y  // 在y方向继续扩展
        
        results[i] = newPoint  // 保存计算出的新位置
      }
      return results  // 返回扩展后的顶点数组
    } else {
      return vertex  // 如果扩展值为零，直接返回原始顶点
    }
  }

  // 在水平方向为候选字之间添加间隙，让候选字在视觉上更容易区分
  // Add gap between horizontal candidates
  func expandHighlightWidth(rect: NSRect, extraSurrounding: CGFloat) -> NSRect {
    var newRect = rect  // 复制原始矩形
    if !nearEmpty(newRect) {  // 只有当矩形不为空时才进行扩展
      newRect.size.width += extraSurrounding      // 增加宽度
      newRect.origin.x -= extraSurrounding / 2    // 向左移动一半距离，保持中心位置
    }
    return newRect  // 返回扩展后的矩形
  }

  // 移除过于接近容器边界的角点，避免在边缘创建不自然的圆角
  // 当高亮区域延伸到容器边缘时，某些角点可能会产生奇怪的视觉效果
  func removeCorner(highlightedPoints: [CGPoint], rightCorners: Set<Int>, containingRect: NSRect) -> Set<Int> {
    if !highlightedPoints.isEmpty && !rightCorners.isEmpty {
      var result = rightCorners  // 复制原始角点集合
      for cornerIndex in rightCorners {
        let corner = highlightedPoints[cornerIndex]  // 获取角点坐标
        // 计算角点到容器上下边界的最小距离
        let dist = min(containingRect.maxY - corner.y, corner.y - containingRect.minY)
        if dist < 1e-2 {  // 如果距离非常小（基本贴边）
          result.remove(cornerIndex)  // 从角点集合中移除这个角点
        }
      }
      return result  // 返回过滤后的角点集合
    } else {
      return rightCorners  // 如果没有高亮点或角点，直接返回原集合
    }
  }

  // 为线性多行布局计算顶点和角点
  // 这个函数处理特殊情况：当包含框分离时的多行高亮
  // swiftlint:disable:next large_tuple
  func linearMultilineFor(body: NSRect, leading: NSRect, trailing: NSRect) -> (Array<NSPoint>, Array<NSPoint>, Set<Int>, Set<Int>) {
    let highlightedPoints, highlightedPoints2: [NSPoint]  // 两组高亮点
    let rightCorners, rightCorners2: Set<Int>             // 两组角点索引
    
    // 处理特殊情况：包含框被分离（首行和末行不相连）
    if nearEmpty(body) && !nearEmpty(leading) && !nearEmpty(trailing) && trailing.maxX < leading.minX {
      // 首行和末行分离，需要分别处理
      highlightedPoints = rectVertex(of: leading)   // 首行的矩形顶点
      highlightedPoints2 = rectVertex(of: trailing) // 末行的矩形顶点
      rightCorners = [2, 3]   // 首行右侧的两个角点需要保持直角
      rightCorners2 = [0, 1]  // 末行左侧的两个角点需要保持直角
    } else {
      // 正常情况：使用多行顶点计算函数
      highlightedPoints = multilineVertex(leadingRect: leading, bodyRect: body, trailingRect: trailing)
      highlightedPoints2 = []  // 第二组顶点为空
      rightCorners = []        // 不需要特殊的直角处理
      rightCorners2 = []
    }
    return (highlightedPoints, highlightedPoints2, rightCorners, rightCorners2)
  }

  // 绘制高亮路径的核心函数，处理候选字和预编辑文本的背景高亮
  // 这是整个高亮系统最复杂的函数，需要考虑多种布局模式和边界情况
  func drawPathCandidate(highlightedRange: NSRange, backgroundRect: NSRect, preeditRect: NSRect, containingRect: NSRect, extraExpansion: Double) -> CGPath? {
    let theme = currentTheme        // 获取当前主题
    let resultingPath: CGMutablePath?  // 最终的绘制路径
    if DEBUG_LAYOUT_LOGS {
      print("[SquirrelView.drawPathCandidate] in range=\(highlightedRange) bg=\(backgroundRect) preedit=\(preeditRect) contain=\(containingRect) extra=\(extraExpansion)")
    }

    // 计算当前包含矩形，考虑额外扩展
    var currentContainingRect = containingRect
    currentContainingRect.size.width += extraExpansion * 2    // 宽度双向扩展
    currentContainingRect.size.height += extraExpansion * 2   // 高度双向扩展
    currentContainingRect.origin.x -= extraExpansion         // 向左扩展
    currentContainingRect.origin.y -= extraExpansion         // 向上扩展

  let halfLinespace = theme.linespace / 2  // 半行间距，用于精确定位
  // 使用实际 inset（候选区垂直 inset 可能为 0）
  let candInset = candidateTextView.textContainerInset

    // 计算内边界框，这是文本实际绘制的区域
    var innerBox = backgroundRect
    innerBox.size.width -= (theme.edgeInset.width + 1) * 2 - 2 * extraExpansion    // 扣除边距和扩展
    innerBox.origin.x += theme.edgeInset.width + 1 - extraExpansion                // 调整起始位置
    innerBox.size.height += 2 * extraExpansion                                     // 垂直方向扩展
    innerBox.origin.y -= extraExpansion                                            // 向下调整
    
    if preeditRange.length == 0 {
      // 无预编辑：顶部从面板内边距开始（去除额外+1像素），底部留出下边内边距
  innerBox.origin.y += candInset.height
  innerBox.size.height -= (candInset.height + theme.edgeInset.height)
    } else {
      // 有预编辑：候选区顶部精确贴到预编辑区域底部
      innerBox.origin.y += preeditRect.size.height
  innerBox.size.height -= candInset.height + preeditRect.size.height
    }
    // 注意：不再对 innerBox 进行半行距的二次位移，避免在首行产生视觉缝隙
    if DEBUG_LAYOUT_LOGS {
      print("[SquirrelView.drawPathCandidate] innerBox=\(innerBox)")
    }

    // 计算外边界框，这是高亮效果的最大范围
    var outerBox = backgroundRect
  // 外边界同样将顶部对齐至预编辑底部，去除圆角/边框的半径补偿，确保无缝衔接
  outerBox.size.height -= preeditRect.size.height - 2 * extraExpansion
  outerBox.size.width -= max(0, theme.hilitedCornerRadius + theme.borderLineWidth) - 2 * extraExpansion
  outerBox.origin.x += max(0.0, theme.hilitedCornerRadius + theme.borderLineWidth) / 2.0 - extraExpansion
  outerBox.origin.y += preeditRect.size.height - extraExpansion

    // 计算有效的圆角半径，考虑扩展效果
    let effectiveRadius = max(0, theme.hilitedCornerRadius + 2 * extraExpansion / theme.hilitedCornerRadius * max(0, theme.cornerRadius - theme.hilitedCornerRadius))
    if DEBUG_LAYOUT_LOGS {
      print("[SquirrelView.drawPathCandidate] outerBox=\(outerBox) effectiveRadius=\(effectiveRadius)")
    }

    // 检查是否使用线性布局模式（支持多行高亮的复杂形状）
  if theme.linear, let highlightedTextRange = convert(range: highlightedRange) {
      // 线性布局：支持复杂的多行高亮形状，如L形、T形等
      let (leadingRect, bodyRect, trailingRect) = multilineRects(forRange: highlightedTextRange, extraSurounding: separatorWidth, bounds: outerBox)
      var (highlightedPoints, highlightedPoints2, rightCorners, rightCorners2) = linearMultilineFor(body: bodyRect, leading: leadingRect, trailing: trailingRect)
      if DEBUG_LAYOUT_LOGS {
        print("[SquirrelView.drawPathCandidate] linear leading=\(leadingRect) body=\(bodyRect) trailing=\(trailingRect)")
      }

      // 扩展顶点以达到适当的边界
      highlightedPoints = enlarge(vertex: highlightedPoints, by: extraExpansion)  // 按指定值扩展
      highlightedPoints = expand(vertex: highlightedPoints, innerBorder: innerBox, outerBorder: outerBox)  // 调整到边界内
      rightCorners = removeCorner(highlightedPoints: highlightedPoints, rightCorners: rightCorners, containingRect: currentContainingRect)  // 移除边缘角点
      // 绘制主要的高亮路径，使用平滑曲线连接
      resultingPath = drawSmoothLines(highlightedPoints, straightCorner: rightCorners, alpha: 0.3*effectiveRadius, beta: 1.4*effectiveRadius)?.mutableCopy()

      // 如果有第二组点（分离的高亮区域），也进行相同处理
      if highlightedPoints2.count > 0 {
        highlightedPoints2 = enlarge(vertex: highlightedPoints2, by: extraExpansion)
        highlightedPoints2 = expand(vertex: highlightedPoints2, innerBorder: innerBox, outerBorder: outerBox)
        rightCorners2 = removeCorner(highlightedPoints: highlightedPoints2, rightCorners: rightCorners2, containingRect: currentContainingRect)
        // 绘制第二个高亮路径
        let highlightedPath2 = drawSmoothLines(highlightedPoints2, straightCorner: rightCorners2, alpha: 0.3*effectiveRadius, beta: 1.4*effectiveRadius)
        if let highlightedPath2 = highlightedPath2 {
          resultingPath?.addPath(highlightedPath2)  // 将第二个路径合并到主路径
        }
      }
  } else if let highlightedTextRange = convert(range: highlightedRange) {
      // 简单矩形布局：适用于单行或简单的矩形高亮
  var highlightedRect = self.contentRect(range: highlightedTextRange)  // 获取文本内容矩形
      if DEBUG_LAYOUT_LOGS { print("[SquirrelView.drawPathCandidate] simple highlightedRect(raw)=\(highlightedRect)") }
      if !nearEmpty(highlightedRect) {
        // 调整高亮矩形的尺寸和位置
        highlightedRect.size.width = backgroundRect.size.width  // 宽度占满背景
        highlightedRect.size.height += theme.linespace          // 增加行间距
    // 以候选容器顶部（seam 顶）为统一基准，消除对 preeditLinespace/圆角/常数的二次叠加导致的累计偏移
    // 原始 y（document->self 后）再加上容器顶部 seam 与文档顶部的差值
    let yBefore = highlightedRect.origin.y
    let seamTop = containingRect.origin.y
    let baseY = yBefore + candInset.height - halfLinespace
    highlightedRect.origin = NSPoint(x: backgroundRect.origin.x, y: seamTop + baseY)
    if DEBUG_LAYOUT_LOGS { print("[SquirrelView.drawPathCandidate] simple anchored to seamTop=\(seamTop) baseY=\(baseY) from y=\(yBefore) -> y=\(highlightedRect.origin.y)") }
        // 进一步修正：如果这是首个候选项，仅当其顶部“接近” seam 时才做 2px 上叠覆盖，
        // 否则保持自然 y（随滚动移动）。
        if preeditRange.length > 0, let first = candidateRanges.first, first.location == highlightedRange.location {
          let epsilon: CGFloat = 0.75 // 允许的对齐误差范围（pt）
          let deltaToSeam = highlightedRect.origin.y - innerBox.minY
          if abs(deltaToSeam) <= epsilon {
            let oldY = highlightedRect.origin.y
            // 不再强制置为 innerBox.minY，只进行轻微上叠覆盖
            let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
            let overlap = 2.0 / scale
            highlightedRect.origin.y -= overlap
            highlightedRect.size.height += overlap
            // 同步边界，避免 expand() 将上叠钳回
            innerBox.origin.y -= overlap
            innerBox.size.height += overlap
            outerBox.origin.y -= overlap
            outerBox.size.height += overlap
            if DEBUG_LAYOUT_LOGS { print("[SquirrelView.drawPathCandidate] simple first-candidate near seam (|Δ|=\(abs(deltaToSeam))) apply overlap: y \(oldY) -> \(highlightedRect.origin.y) (overlap=\(overlap))") }
          }
        }
        if DEBUG_LAYOUT_LOGS { print("[SquirrelView.drawPathCandidate] simple highlightedRect(adjusted)=\(highlightedRect)") }
        
        // 如果高亮到了文本末尾，额外增加底部空间
        if highlightedRange.upperBound == (textView.string as NSString).length {
          highlightedRect.size.height += candInset.height - halfLinespace
        }
        
        // 如果高亮从文本开始位置开始，额外增加顶部空间
        if highlightedRange.location - (preeditRange == .empty ? 0 : preeditRange.upperBound) <= 1 {
          if preeditRange.length == 0 {
            // 没有预编辑文本时的调整
            highlightedRect.size.height += candInset.height - halfLinespace
            highlightedRect.origin.y -= candInset.height - halfLinespace
          } else {
      // 有预编辑文本时：不再额外叠加圆角补偿，避免首行以外候选的累计误差
      // 保持与首项的一致：顶部贴合逻辑仅在上面的 first-candidate 分支执行
          }
        }

        // 生成矩形的顶点并进行边界调整
        var highlightedPoints = rectVertex(of: highlightedRect)
        highlightedPoints = enlarge(vertex: highlightedPoints, by: extraExpansion)  // 扩展顶点
        highlightedPoints = expand(vertex: highlightedPoints, innerBorder: innerBox, outerBorder: outerBox)  // 边界限制
        // 绘制矩形高亮路径，所有角都是圆角
        resultingPath = drawSmoothLines(highlightedPoints, straightCorner: Set(), alpha: effectiveRadius*0.3, beta: effectiveRadius*1.4)?.mutableCopy()
      } else {
        resultingPath = nil  // 空矩形不绘制
      }
    } else {
      resultingPath = nil  // 无法转换文本范围时不绘制
    }
    if DEBUG_LAYOUT_LOGS, let p = resultingPath {
      let bb = p.boundingBox
      let seamTop = preeditRect.maxY
      print("[SquirrelView.drawPathCandidate] bbox minY=\(bb.minY) maxY=\(bb.maxY) height=\(bb.height) seamTop(preedit.maxY)=\(seamTop) deltaTop=\(seamTop - bb.minY)")
    }
    return resultingPath  // 返回最终的绘制路径
  }

  // 雕刻内边距：仅收缩左右与底边，保留顶部 y 不变，避免破坏与预编辑的无缝“分区缝”。
  func carveInset(rect: NSRect) -> NSRect {
    var newRect = rect
  // 同时考虑 borderLineWidth（实际描边宽度），否则会出现 0.5~1px 的可见高度残差
  let inset = currentTheme.hilitedCornerRadius + currentTheme.borderWidth
  let stroke = currentTheme.borderLineWidth
  newRect.size.height -= (inset + stroke)   // 仅减少底边高度（顶部 seam 不动）
    newRect.size.width -= inset * 2           // 左右都缩进
    newRect.origin.x += inset                 // 左侧右移
    // 注意：不修改 origin.y，以保持顶部 seam 完整贴合
    return newRect
  }

  // 创建一个等边三角形的顶点数组，用于绘制翻页按钮
  // 三角形的顶点按逆时针方向排列：顶点在上，底边在下
  func triangle(center: NSPoint, radius: CGFloat) -> [NSPoint] {
    [NSPoint(x: center.x, y: center.y + radius),                                    // 顶点（正上方）
     NSPoint(x: center.x + 0.5 * sqrt(3) * radius, y: center.y - 0.5 * radius),   // 右下角顶点
     NSPoint(x: center.x - 0.5 * sqrt(3) * radius, y: center.y - 0.5 * radius)]   // 左下角顶点
  }

  // 创建翻页控制图层，绘制上一页和下一页的三角形按钮
  // 返回包含翻页按钮的图层以及用于点击检测的路径
  func pagingLayer(theme: SquirrelTheme, preeditRect: CGRect) -> (CAShapeLayer, CGPath?, CGPath?) {
    let layer = CAShapeLayer()  // 创建主图层容器
    // 检查是否需要显示翻页按钮：主题启用翻页显示 且 (可以上翻 或 可以下翻)
    guard theme.showPaging && (canPageUp || canPageDown) else { 
      return (layer, nil, nil)  // 不需要翻页时返回空图层
    }
    // 确保有候选字可用于计算位置
    guard let firstCandidate = candidateRanges.first, let range = convert(range: firstCandidate) else { 
      return (layer, nil, nil) 
    }
    
    // 计算翻页按钮的基本尺寸
    var height = contentRect(range: range).height  // 获取第一个候选字的高度作为基准
    // 计算预编辑文本的有效高度，包括间距和圆角
    let preeditHeight = max(0, preeditRect.height + theme.preeditLinespace / 2 + theme.hilitedCornerRadius / 2 - theme.edgeInset.height) + theme.edgeInset.height - theme.linespace / 2
    height += theme.linespace  // 增加行间距
    
    // 计算三角形按钮的半径，不能超过翻页区域的一半，也不能过大
    let radius = min(0.5 * theme.pagingOffset, 2 * height / 9)
    // 计算有效的圆角半径，用于平滑三角形的边缘
    let effectiveRadius = min(theme.cornerRadius, 0.6 * radius)
    
    // 创建基础三角形路径，使用平滑线条处理
    guard let trianglePath = drawSmoothLines(
      triangle(center: .zero, radius: radius),    // 在原点创建三角形
      straightCorner: [],                         // 不保留直角，全部使用圆角
      alpha: 0.3 * effectiveRadius,               // 圆角平滑度参数
      beta: 1.4 * effectiveRadius                 // 圆角大小参数
    ) else {
      return (layer, nil, nil)  // 如果无法创建三角形路径，返回空
    }
    
    var downPath: CGPath?  // 下一页按钮的路径
    var upPath: CGPath?    // 上一页按钮的路径
    
    // 如果可以下翻页，创建向下的三角形按钮
    if canPageDown {
      // 计算下翻按钮的位置变换：水平居中在翻页区域，垂直位置在候选字下方
      var downTransform = CGAffineTransform(translationX: 0.5 * theme.pagingOffset, y: 2 * height / 3 + preeditHeight)
      let downLayer = shapeFromPath(path: trianglePath.copy(using: &downTransform))  // 应用变换创建图层
      downLayer.fillColor = theme.backgroundColor.cgColor  // 设置填充颜色与背景相同
      downPath = trianglePath.copy(using: &downTransform)  // 保存变换后的路径用于点击检测
      layer.addSublayer(downLayer)  // 将下翻按钮添加到主图层
    }
    
    // 如果可以上翻页，创建向上的三角形按钮
    if canPageUp {
      // 计算上翻按钮的位置变换：先旋转180度（指向上方），然后平移到合适位置
      var upTransform = CGAffineTransform(rotationAngle: .pi).translatedBy(x: -0.5 * theme.pagingOffset, y: -height / 3 - preeditHeight)
      let upLayer = shapeFromPath(path: trianglePath.copy(using: &upTransform))  // 应用变换创建图层
      upLayer.fillColor = theme.backgroundColor.cgColor  // 设置填充颜色与背景相同
      upPath = trianglePath.copy(using: &upTransform)     // 保存变换后的路径用于点击检测
      layer.addSublayer(upLayer)  // 将上翻按钮添加到主图层
    }
    
    // 返回包含所有翻页按钮的图层，以及用于点击检测的路径
    return (layer, downPath, upPath)
  }
}
