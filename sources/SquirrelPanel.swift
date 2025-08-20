//
//  SquirrelPanel.swift
//  Squirrel
//
//  Created by Leo Liu on 5/10/24.
//

// 导入 AppKit，这是 macOS 应用界面开发的核心库
// 就像导入一个画画工具箱，里面有各种绘制界面的工具
import AppKit

// 定义鼠须管面板类，这是输入法候选字窗口的核心
// final 表示这个类不能被继承，NSPanel 是 macOS 面板窗口的基类
// 就像创建一个特殊的小窗口，专门用来显示候选字
final class SquirrelPanel: NSPanel {
  // 类的属性定义，就像这个面板的各种特征和工具
  private let view: SquirrelView            // 主要的显示视图，负责绘制候选字
  private let back: NSVisualEffectView      // 背景效果视图，提供毛玻璃等视觉效果
  var inputController: SquirrelInputController?  // 输入控制器，用来处理用户的输入操作

  var position: NSRect                      // 面板的位置信息，记录在屏幕上的坐标
  private var screenRect: NSRect = .zero    // 当前屏幕的尺寸和位置
  private var maxHeight: CGFloat = 0        // 面板的最大高度

  // 状态消息相关的属性
  private var statusMessage: String = ""    // 存储要显示的状态消息文本
  private var statusTimer: Timer?           // 定时器，用来控制状态消息的显示时间

  // 输入相关的状态变量，记录当前输入法的各种状态
  private var preedit: String = ""          // 预编辑文本（还未确认的输入内容）
  private var selRange: NSRange = .empty    // 选中的文本范围
  private var caretPos: Int = 0             // 光标位置（插入点位置）
  private var candidates: [String] = .init() // 候选字列表
  private var comments: [String] = .init()   // 候选字的注释（如拼音、解释等）
  private var labels: [String] = .init()     // 候选字的标签（如 1. 2. 3. 等）
  private var index: Int = 0                 // 当前选中的候选字索引
  private var cursorIndex: Int = 0           // 鼠标悬停的候选字索引
  
  // 滚动相关的变量，处理鼠标滚轮和触摸板手势
  private var scrollDirection: CGVector = .zero    // 滚动方向和距离
  private var scrollTime: Date = .distantPast      // 最后一次滚动的时间
  
  // 分页相关的变量，处理候选字的翻页
  private var page: Int = 0                 // 当前页码
  private var lastPage: Bool = true         // 是否是最后一页
  private var pagingUp: Bool?               // 是否正在向上翻页

  // 初始化函数，创建一个新的鼠须管面板
  // position 参数指定面板在屏幕上的初始位置
  init(position: NSRect) {
    self.position = position                          // 保存位置信息
    self.view = SquirrelView(frame: position)        // 创建主显示视图
    self.back = NSVisualEffectView()                 // 创建背景效果视图
    
    // 调用父类的初始化方法，设置面板的基本属性
    super.init(contentRect: position, styleMask: .nonactivatingPanel, backing: .buffered, defer: true)
    
    // 设置面板的显示层级，让它显示在最顶层
    self.level = .init(Int(CGShieldingWindowLevel()))
    self.hasShadow = true        // 启用阴影效果
    self.isOpaque = false        // 设置为非不透明（允许透明效果）
    self.backgroundColor = .clear // 设置背景颜色为透明
    
    // 配置背景效果视图的属性
    back.blendingMode = .behindWindow    // 设置混合模式
    back.material = .hudWindow           // 设置材质为 HUD 窗口样式
    back.state = .active                 // 设置为活跃状态
    back.wantsLayer = true               // 启用图层
    back.layer?.mask = view.shape        // 使用主视图的形状作为遮罩
    
    // 创建内容视图并添加子视图
    let contentView = NSView()
    contentView.addSubview(back)         // 添加背景视图
    contentView.addSubview(view)         // 添加主视图
    contentView.addSubview(view.textView) // 添加文本视图
    self.contentView = contentView       // 设置为面板的内容视图
  }

  // 以下是一些计算属性，用来快速获取当前主题的设置
  // 这些属性就像主题配置的快捷方式
  
  var linear: Bool {
    view.currentTheme.linear              // 是否使用线性布局（水平排列候选字）
  }
  var vertical: Bool {
    view.currentTheme.vertical            // 是否使用垂直显示模式
  }
  var inlinePreedit: Bool {
    view.currentTheme.inlinePreedit       // 是否在输入位置内联显示预编辑文本
  }
  var inlineCandidate: Bool {
    view.currentTheme.inlineCandidate     // 是否在输入位置内联显示候选字
  }

  // 重写事件处理方法，处理各种用户交互
  // 这个方法就像一个事件分发员，根据不同的事件类型执行不同的操作
  // swiftlint:disable:next cyclomatic_complexity
  override func sendEvent(_ event: NSEvent) {
    switch event.type {
    case .leftMouseDown:  // 鼠标左键按下
      // 获取点击位置对应的候选字索引和翻页信息
      let (index, _, pagingUp) =  view.click(at: mousePosition())
      if let pagingUp {
        self.pagingUp = pagingUp  // 记录翻页方向
      } else {
        self.pagingUp = nil
      }
      // 如果点击了有效的候选字，记录选中的索引
      if let index, index >= 0 && index < candidates.count {
        self.index = index
      }
    case .leftMouseUp:  // 鼠标左键释放
      // 获取释放位置的信息
      let (index, preeditIndex, pagingUp) = view.click(at: mousePosition())

      // 如果是翻页操作，并且方向与按下时一致
      if let pagingUp, pagingUp == self.pagingUp {
        _ = inputController?.page(up: pagingUp)  // 执行翻页
      } else {
        self.pagingUp = nil
      }
      
      // 如果点击了预编辑文本区域，移动光标
      if let preeditIndex, preeditIndex >= 0 && preeditIndex < preedit.utf16.count {
        if preeditIndex < caretPos {
          _ = inputController?.moveCaret(forward: true)   // 向前移动光标
        } else if preeditIndex > caretPos {
          _ = inputController?.moveCaret(forward: false)  // 向后移动光标
        }
      }
      
      // 如果点击了候选字，并且与按下时是同一个候选字，则选择它
      if let index, index == self.index && index >= 0 && index < candidates.count {
        _ = inputController?.selectCandidate(index)
      }
    case .mouseEntered:  // 鼠标进入面板区域
      acceptsMouseMovedEvents = true   // 开始接收鼠标移动事件
      
    case .mouseExited:   // 鼠标离开面板区域
      acceptsMouseMovedEvents = false  // 停止接收鼠标移动事件
      // 如果鼠标悬停的候选字与当前选中的不同，恢复高亮显示
      if cursorIndex != index {
        update(preedit: preedit, selRange: selRange, caretPos: caretPos, candidates: candidates, comments: comments, labels: labels, highlighted: index, page: page, lastPage: lastPage, update: false)
      }
      pagingUp = nil  // 清除翻页状态
      
    case .mouseMoved:    // 鼠标在面板内移动
      let (index, _, _) = view.click(at: mousePosition())
      // 如果鼠标悬停在新的候选字上，更新高亮显示
      if let index = index, cursorIndex != index && index >= 0 && index < candidates.count {
        update(preedit: preedit, selRange: selRange, caretPos: caretPos, candidates: candidates, comments: comments, labels: labels, highlighted: index, page: page, lastPage: lastPage, update: false)
      }
    case .scrollWheel:   // 滚轮或触摸板滚动事件
      if event.phase == .began {  // 滚动开始
        scrollDirection = .zero
        // Scrollboard span - 触摸板滚动跨度
      } else if event.phase == .ended || (event.phase == .init(rawValue: 0) && event.momentumPhase != .init(rawValue: 0)) {
        // 滚动结束或惯性滚动
        // 根据滚动方向和距离决定是否翻页
        if abs(scrollDirection.dx) > abs(scrollDirection.dy) && abs(scrollDirection.dx) > 10 {
          // 水平滚动距离较大，根据垂直模式调整翻页方向
          _ = inputController?.page(up: (scrollDirection.dx < 0) == vertical)
        } else if abs(scrollDirection.dx) < abs(scrollDirection.dy) && abs(scrollDirection.dy) > 10 {
          // 垂直滚动距离较大
          _ = inputController?.page(up: scrollDirection.dy > 0)
        }
        scrollDirection = .zero
        // Mouse scroll wheel - 鼠标滚轮
      } else if event.phase == .init(rawValue: 0) && event.momentumPhase == .init(rawValue: 0) {
        // 处理鼠标滚轮事件（不是触摸板手势）
        if scrollTime.timeIntervalSinceNow < -1 {  // 如果距离上次滚动超过1秒
          scrollDirection = .zero  // 重置滚动方向
        }
        scrollTime = .now  // 更新滚动时间
        
        // 累积同方向的滚动距离
        if (scrollDirection.dy >= 0 && event.scrollingDeltaY > 0) || (scrollDirection.dy <= 0 && event.scrollingDeltaY < 0) {
          scrollDirection.dy += event.scrollingDeltaY
        } else {
          scrollDirection = .zero  // 方向改变时重置
        }
        
        // 如果滚动距离足够大，执行翻页
        if abs(scrollDirection.dy) > 10 {
          _ = inputController?.page(up: scrollDirection.dy > 0)
          scrollDirection = .zero
        }
      } else {
        // 其他滚动阶段，累积滚动距离
        scrollDirection.dx += event.scrollingDeltaX
        scrollDirection.dy += event.scrollingDeltaY
      }
    default:
      break  // 其他事件类型不处理
    }
    super.sendEvent(event)  // 调用父类的事件处理方法
  }

  // 隐藏面板的方法
  func hide() {
    statusTimer?.invalidate()  // 取消状态消息定时器
    statusTimer = nil
    orderOut(nil)             // 将面板从屏幕上移除
    maxHeight = 0             // 重置最大高度
  }

  // 主要的更新函数，用来添加文本属性并显示来自 librime 的输出
  // 这是整个面板最核心的函数，就像画家的调色板，把各种元素组合成最终的显示效果
  // swiftlint:disable:next cyclomatic_complexity function_parameter_count
  func update(preedit: String, selRange: NSRange, caretPos: Int, candidates: [String], comments: [String], labels: [String], highlighted index: Int, page: Int, lastPage: Bool, update: Bool) {
    
    // 如果需要更新数据，就保存新的状态信息
    if update {
      self.preedit = preedit        // 预编辑文本
      self.selRange = selRange      // 选中范围
      self.caretPos = caretPos      // 光标位置
      self.candidates = candidates  // 候选字列表
      self.comments = comments      // 注释列表
      self.labels = labels          // 标签列表
      self.index = index           // 选中索引
      self.page = page             // 页码
      self.lastPage = lastPage     // 是否最后一页
    }
    cursorIndex = index  // 更新鼠标悬停索引

    // 如果有候选字或预编辑文本，清除状态消息
    if !candidates.isEmpty || !preedit.isEmpty {
      statusMessage = ""           // 清空状态消息
      statusTimer?.invalidate()    // 取消状态消息定时器
      statusTimer = nil
    } else {
      // 如果没有候选字和预编辑文本，处理状态消息显示
      if !statusMessage.isEmpty {
        show(status: statusMessage)  // 显示状态消息
        statusMessage = ""           // 清空状态消息
      } else if statusTimer == nil {
        hide()                      // 如果没有定时器运行，隐藏面板
      }
      return  // 提前返回，不继续处理候选字显示
    }

    let theme = view.currentTheme  // 获取当前主题
    currentScreen()               // 更新当前屏幕信息

    // 创建富文本对象，用来存储所有要显示的文本和样式
    let text = NSMutableAttributedString()
    let preeditRange: NSRange           // 预编辑文本的范围
    let highlightedPreeditRange: NSRange // 预编辑文本中高亮部分的范围

    // 处理预编辑文本（用户正在输入但还未确认的文本）
    if !preedit.isEmpty {
      // 计算预编辑文本的范围
      preeditRange = NSRange(location: 0, length: preedit.utf16.count)
      highlightedPreeditRange = selRange  // 高亮部分就是选中范围

      // 创建预编辑文本的富文本
      let line = NSMutableAttributedString(string: preedit)
      line.addAttributes(theme.preeditAttrs, range: preeditRange)  // 添加预编辑文本样式
      line.addAttributes(theme.preeditHighlightedAttrs, range: selRange)  // 添加高亮样式到选中部分
      text.append(line)  // 将预编辑文本添加到总文本中

      // 设置预编辑文本的段落样式
      text.addAttribute(.paragraphStyle, value: theme.preeditParagraphStyle, range: NSRange(location: 0, length: text.length))
      
      // 如果有候选字，在预编辑文本后添加换行符
      if !candidates.isEmpty {
        text.append(NSAttributedString(string: "\n", attributes: theme.preeditAttrs))
      }
    } else {
      // 如果没有预编辑文本，设置范围为空
      preeditRange = .empty
      highlightedPreeditRange = .empty
    }

    // 处理候选字列表
    var candidateRanges = [NSRange]()  // 存储每个候选字在文本中的范围
    
    // 遍历每个候选字
    for i in 0..<candidates.count {
      // 根据是否是当前选中的候选字，选择不同的样式
      let attrs = i == index ? theme.highlightedAttrs : theme.attrs  // 候选字样式
      let labelAttrs = i == index ? theme.labelHighlightedAttrs : theme.labelAttrs  // 标签样式
      let commentAttrs = i == index ? theme.commentHighlightedAttrs : theme.commentAttrs  // 注释样式

      // 生成候选字标签（如 1. 2. 3. 或 A. B. C.）
      let label = if theme.candidateFormat.contains(/\[label\]/) {
        if labels.count > 1 && i < labels.count {
          labels[i]  // 使用自定义标签
        } else if labels.count == 1 && i < labels.first!.count {
          // 自定义格式：A. B. C...
          String(labels.first![labels.first!.index(labels.first!.startIndex, offsetBy: i)])
        } else {
          // 默认格式：1. 2. 3...
          "\(i+1)"
        }
      } else {
        ""  // 不显示标签
      }

      // 获取候选字和注释文本，并进行标准化处理
      let candidate = candidates[i].precomposedStringWithCanonicalMapping  // 候选字文本
      let comment = comments[i].precomposedStringWithCanonicalMapping      // 注释文本

      // 根据候选字格式模板创建富文本行
      let line = NSMutableAttributedString(string: theme.candidateFormat, attributes: labelAttrs)
      
      // 为 [candidate] 占位符区域添加候选字样式
      for range in line.string.ranges(of: /\[candidate\]/) {
        let convertedRange = convert(range: range, in: line.string)
        line.addAttributes(attrs, range: convertedRange)
        // 如果候选字很短，防止换行
        if candidate.count <= 5 {
          line.addAttribute(.noBreak, value: true, range: NSRange(location: convertedRange.location+1, length: convertedRange.length-1))
        }
      }
      
      // 为 [comment] 占位符区域添加注释样式
      for range in line.string.ranges(of: /\[comment\]/) {
        line.addAttributes(commentAttrs, range: convert(range: range, in: line.string))
      }
      // 替换占位符为实际内容
      line.mutableString.replaceOccurrences(of: "[label]", with: label, range: NSRange(location: 0, length: line.length))
      let labeledLine = line.copy() as! NSAttributedString  // 保存带标签的行，用于后续计算
      line.mutableString.replaceOccurrences(of: "[candidate]", with: candidate, range: NSRange(location: 0, length: line.length))
      line.mutableString.replaceOccurrences(of: "[comment]", with: comment, range: NSRange(location: 0, length: line.length))

      // 如果行很短，防止换行
      if line.length <= 10 {
        line.addAttribute(.noBreak, value: true, range: NSRange(location: 1, length: line.length-1))
      }

      // 创建行分隔符（线性布局用空格，非线性用换行符）
      let lineSeparator = NSAttributedString(string: linear ? "  " : "\n", attributes: attrs)
      if i > 0 {  // 除了第一个候选字，其他都要加分隔符
        text.append(lineSeparator)
      }
      // 处理垂直模式的分隔符
      let str = lineSeparator.mutableCopy() as! NSMutableAttributedString
      if vertical {
        str.addAttribute(.verticalGlyphForm, value: 1, range: NSRange(location: 0, length: str.length))
      }
      view.separatorWidth = str.boundingRect(with: .zero).width  // 计算分隔符宽度

      // 设置段落样式
      let paragraphStyleCandidate = (i == 0 ? theme.firstParagraphStyle : theme.paragraphStyle).mutableCopy() as! NSMutableParagraphStyle
      
      // 线性布局的特殊处理
      if linear {
        paragraphStyleCandidate.paragraphSpacingBefore -= theme.linespace
        paragraphStyleCandidate.lineSpacing = theme.linespace
      }
      
      // 非线性布局且有标签时，设置标签缩进
      if !linear, let labelEnd = labeledLine.string.firstMatch(of: /\[(candidate|comment)\]/)?.range.lowerBound {
        let labelString = labeledLine.attributedSubstring(from: NSRange(location: 0, length: labelEnd.utf16Offset(in: labeledLine.string)))
        let labelWidth = labelString.boundingRect(with: .zero, options: [.usesLineFragmentOrigin]).width
        paragraphStyleCandidate.headIndent = labelWidth  // 设置首行缩进
      }
      
      line.addAttribute(.paragraphStyle, value: paragraphStyleCandidate, range: NSRange(location: 0, length: line.length))

      // 记录候选字在文本中的范围，并添加到总文本中
      candidateRanges.append(NSRange(location: text.length, length: line.length))
      text.append(line)
    }

    // 文本处理完成！
    // 将处理好的富文本设置到文本视图中
    view.textView.textContentStorage?.attributedString = text
    // 设置文本布局方向（垂直或水平）
    view.textView.setLayoutOrientation(vertical ? .vertical : .horizontal)
    // 绘制视图，包括候选字高亮、翻页按钮等
    view.drawView(candidateRanges: candidateRanges, hilightedIndex: index, preeditRange: preeditRange, highlightedPreeditRange: highlightedPreeditRange, canPageUp: page > 0, canPageDown: !lastPage)
    // 显示面板
    show()
  }

  // 更新状态消息的函数
  // longMessage 是完整的消息，shortMessage 是简短版本
  func updateStatus(long longMessage: String, short shortMessage: String) {
    let theme = view.currentTheme
    // 根据主题设置决定显示哪种消息
    switch theme.statusMessageType {
    case .mix:   // 混合模式：优先显示短消息，没有就显示长消息
      statusMessage = shortMessage.isEmpty ? longMessage : shortMessage
    case .long:  // 长消息模式：只显示长消息
      statusMessage = longMessage
    case .short: // 短消息模式：优先显示短消息，没有就显示长消息的首字符
      if !shortMessage.isEmpty {
        statusMessage = shortMessage
      } else if let initial = longMessage.first {
        statusMessage = String(initial)  // 只显示首字符
      } else {
        statusMessage = ""               // 没有消息就设为空
      }
    }
  }

  // 加载配置的函数
  // config 是配置对象，isDark 表示是否为深色模式
  func load(config: SquirrelConfig, forDarkMode isDark: Bool) {
    if isDark {
      // 为深色模式创建和加载主题
      view.darkTheme = SquirrelTheme()
      view.darkTheme.load(config: config, dark: true)
    } else {
      // 为浅色模式创建和加载主题
      view.lightTheme = SquirrelTheme()
      view.lightTheme.load(config: config, dark: isDark)
    }
  }
}

// 私有扩展，包含内部使用的辅助方法
private extension SquirrelPanel {
  // 获取鼠标在面板中的位置
  func mousePosition() -> NSPoint {
    var point = NSEvent.mouseLocation      // 获取鼠标在屏幕上的位置
    point = self.convertPoint(fromScreen: point)  // 转换为面板坐标系
    return view.convert(point, from: nil)  // 转换为视图坐标系
  }

  // 获取当前屏幕信息
  func currentScreen() {
    if let screen = NSScreen.main {  // 先尝试获取主屏幕
      screenRect = screen.frame
    }
    // 查找包含面板位置的屏幕
    for screen in NSScreen.screens where screen.frame.contains(position.origin) {
      screenRect = screen.frame
      break
    }
  }

  // 计算文本的最大宽度
  func maxTextWidth() -> CGFloat {
    let theme = view.currentTheme
    let font: NSFont = theme.font
    let fontScale = font.pointSize / 12  // 字体缩放比例
    // 根据字体大小和显示模式计算文本宽度比例
    let textWidthRatio = min(1, 1 / (vertical ? 4 : 3) + fontScale / 12)
    let maxWidth = if vertical {
      // 垂直模式：基于屏幕高度计算
      screenRect.height * textWidthRatio - theme.edgeInset.height * 2
    } else {
      // 水平模式：基于屏幕宽度计算
      screenRect.width * textWidthRatio - theme.edgeInset.width * 2
    }
    return maxWidth
  }

  // 获取窗口大小，这个窗口将成为 SquirrelView.drawRect 中的 dirtyRect
  // 这是显示面板的核心函数，负责计算位置、大小并显示面板
  // swiftlint:disable:next cyclomatic_complexity
  func show() {
    currentScreen()  // 更新屏幕信息
    let theme = view.currentTheme
    
    // 如果没有深色主题，使用浅色外观
    if !view.darkTheme.available {
      self.appearance = NSAppearance(named: .aqua)
    }

    // 根据屏幕大小限制文本长度，防止文本过长
    let textWidth = maxTextWidth()
    let maxTextHeight = vertical ? screenRect.width - theme.edgeInset.width * 2 : screenRect.height - theme.edgeInset.height * 2
    view.textContainer.size = NSSize(width: textWidth, height: maxTextHeight)

    var panelRect = NSRect.zero  // 面板的矩形区域
    // 在垂直模式下，宽度和高度会互换
    var contentRect = view.contentRect
    
    // 如果启用了记忆大小功能，进行特殊处理
    if theme.memorizeSize && (vertical && position.midY / screenRect.height < 0.5) ||
        (vertical && position.minX + max(contentRect.width, maxHeight) + theme.edgeInset.width * 2 > screenRect.maxX) {
      if contentRect.width >= maxHeight {
        maxHeight = contentRect.width  // 更新最大高度
      } else {
        contentRect.size.width = maxHeight  // 使用记忆的高度
        view.textContainer.size = NSSize(width: maxHeight, height: maxTextHeight)
      }
    }

    if vertical {
      // 垂直模式的面板大小和位置计算
      panelRect.size = NSSize(width: min(0.95 * screenRect.width, contentRect.height + theme.edgeInset.height * 2),
                              height: min(0.95 * screenRect.height, contentRect.width + theme.edgeInset.width * 2) + theme.pagingOffset)

      // 为了避免打字时上下跳动，在上半屏幕打字时使用下半屏幕，反之亦然
      if position.midY / screenRect.height >= 0.5 {
        panelRect.origin.y = position.minY - SquirrelTheme.offsetHeight - panelRect.height + theme.pagingOffset
      } else {
        panelRect.origin.y = position.maxY + SquirrelTheme.offsetHeight
      }
      
      // 让第一个候选字固定在光标左侧
      panelRect.origin.x = position.minX - panelRect.width - SquirrelTheme.offsetHeight
      if view.preeditRange.length > 0, let preeditTextRange = view.convert(range: view.preeditRange) {
        let preeditRect = view.contentRect(range: preeditTextRange)
        panelRect.origin.x += preeditRect.height + theme.edgeInset.width
      }
    } else {
      // 水平模式的面板大小和位置计算
      panelRect.size = NSSize(width: min(0.95 * screenRect.width, contentRect.width + theme.edgeInset.width * 2),
                              height: min(0.95 * screenRect.height, contentRect.height + theme.edgeInset.height * 2))
      panelRect.size.width += theme.pagingOffset
      panelRect.origin = NSPoint(x: position.minX - theme.pagingOffset, y: position.minY - SquirrelTheme.offsetHeight - panelRect.height)
    }
    // 确保面板不会超出屏幕边界
    if panelRect.maxX > screenRect.maxX {
      panelRect.origin.x = screenRect.maxX - panelRect.width  // 右边界调整
    }
    if panelRect.minX < screenRect.minX {
      panelRect.origin.x = screenRect.minX                    // 左边界调整
    }
    if panelRect.minY < screenRect.minY {
      if vertical {
        panelRect.origin.y = screenRect.minY                  // 垂直模式的下边界调整
      } else {
        panelRect.origin.y = position.maxY + SquirrelTheme.offsetHeight  // 水平模式改为显示在上方
      }
    }
    if panelRect.maxY > screenRect.maxY {
      panelRect.origin.y = screenRect.maxY - panelRect.height // 上边界调整
    }
    if panelRect.minY < screenRect.minY {
      panelRect.origin.y = screenRect.minY                    // 最终下边界调整
    }
    self.setFrame(panelRect, display: true)  // 设置面板的最终位置和大小

    // 旋转视图，这是垂直模式的核心！
    if vertical {
      contentView!.boundsRotation = -90  // 将内容视图逆时针旋转90度
      contentView!.setBoundsOrigin(NSPoint(x: 0, y: panelRect.width))
    } else {
      contentView!.boundsRotation = 0    // 水平模式不旋转
      contentView!.setBoundsOrigin(.zero)
    }
    view.textView.boundsRotation = 0     // 文本视图始终不旋转
    view.textView.setBoundsOrigin(.zero)

    // 设置各个视图的框架
    view.frame = contentView!.bounds
    view.textView.frame = contentView!.bounds
    view.textView.frame.size.width -= theme.pagingOffset       // 为翻页按钮留出空间
    view.textView.frame.origin.x += theme.pagingOffset
    view.textView.textContainerInset = theme.edgeInset         // 设置文本容器的内边距

    // 处理半透明背景效果
    if theme.translucency {
      back.frame = contentView!.bounds
      back.frame.size.width += theme.pagingOffset
      back.appearance = NSApp.effectiveAppearance  // 使用系统当前外观
      back.isHidden = false                        // 显示背景视图
    } else {
      back.isHidden = true                         // 隐藏背景视图
    }
    
    alphaValue = theme.alpha  // 设置面板透明度
    invalidateShadow()        // 刷新阴影
    orderFront(nil)           // 将面板显示到最前面
    // voila! - 大功告成！
  }

  // 显示状态消息的函数
  func show(status message: String) {
    let theme = view.currentTheme
    // 创建状态消息的富文本
    let text = NSMutableAttributedString(string: message, attributes: theme.attrs)
    text.addAttribute(.paragraphStyle, value: theme.paragraphStyle, range: NSRange(location: 0, length: text.length))
    
    // 设置文本内容和布局
    view.textContentStorage.attributedString = text
    view.textView.setLayoutOrientation(vertical ? .vertical : .horizontal)
    
    // 绘制状态消息视图
    view.drawView(candidateRanges: [NSRange(location: 0, length: text.length)], hilightedIndex: -1,
                  preeditRange: .empty, highlightedPreeditRange: .empty, canPageUp: false, canPageDown: false)
    show()  // 显示面板

    // 设置定时器，一定时间后自动隐藏状态消息
    statusTimer?.invalidate()
    statusTimer = Timer.scheduledTimer(withTimeInterval: SquirrelTheme.showStatusDuration, repeats: false) { _ in
      self.hide()
    }
  }

  // 转换字符串范围到 NSRange 的工具函数
  func convert(range: Range<String.Index>, in string: String) -> NSRange {
    let startPos = range.lowerBound.utf16Offset(in: string)  // 获取起始位置的 UTF-16 偏移量
    let endPos = range.upperBound.utf16Offset(in: string)    // 获取结束位置的 UTF-16 偏移量
    return NSRange(location: startPos, length: endPos - startPos)  // 创建 NSRange
  }
}
