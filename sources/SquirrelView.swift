//
//  SquirrelView.swift
//  Squirrel
//
//  Created by Leo Liu on 5/9/24.
//

// 导入 AppKit，这是 macOS 应用界面开发的核心库
// 就像导入一个绘画工具箱，里面有各种绘制界面的工具
import AppKit

// 定义一个私有的文本布局代理类
// 这个类就像一个文本排版师，负责决定文字应该如何换行
private class SquirrelLayoutDelegate: NSObject, NSTextLayoutManagerDelegate {
  // 这个函数决定是否应该在某个位置换行
  // 就像决定一行文字写满了是否要另起一行
  func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, shouldBreakLineBefore location: any NSTextLocation, hyphenating: Bool) -> Bool {
    // 计算当前位置在文本中的索引
    let index = textLayoutManager.offset(from: textLayoutManager.documentRange.location, to: location)
    
    // 检查当前位置的文本是否有 "noBreak" 属性（不换行属性）
    if let attributes = textLayoutManager.textContainer?.textView?.textContentStorage?.attributedString?.attributes(at: index, effectiveRange: nil),
       let noBreak = attributes[.noBreak] as? Bool, noBreak {
      return false  // 如果设置了不换行，就返回 false（不要换行）
    }
    return true  // 否则允许换行
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
  // 类的属性定义，就像这个视图的各种特征和工具
  let textView: NSTextView                    // 文本视图，负责显示和管理文本内容
  let scrollView: NSScrollView               // 滚动视图，裁切超出可见区域并显示滚动条

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

  // 初始化函数，创建一个新的鼠须管视图
  override init(frame frameRect: NSRect) {
    squirrelLayoutDelegate = SquirrelLayoutDelegate()  // 创建布局代理
  textView = NSTextView(frame: frameRect)            // 创建文本视图
  scrollView = NSScrollView(frame: frameRect)        // 创建滚动视图
    
    // 配置文本视图的属性
    textView.drawsBackground = false                   // 不绘制背景（透明背景）
    textView.isEditable = false                        // 不可编辑（只显示）
    textView.isSelectable = false                      // 不可选择文本
  textView.textLayoutManager?.delegate = squirrelLayoutDelegate  // 设置布局代理
    
    super.init(frame: frameRect)                       // 调用父类初始化
    
    // 进一步配置
  textContainer.lineFragmentPadding = 0              // 设置行片段内边距为0
    self.wantsLayer = true                             // 启用图层支持
    self.layer?.masksToBounds = true                   // 图层内容不超出边界
  self.autoresizingMask = [.width, .height]

    // 配置滚动容器与文本视图关系
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.scrollerStyle = .overlay
    scrollView.borderType = .noBorder
    scrollView.autohidesScrollers = true
  scrollView.usesPredominantAxisScrolling = true
    scrollView.documentView = textView

    // 让文本在垂直方向可扩展，由滚动容器裁切
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
  if let container = textView.textContainer {
      container.widthTracksTextView = true
      container.heightTracksTextView = false
  container.containerSize = NSSize(width: frameRect.width, height: CGFloat.greatestFiniteMagnitude)
    }

  // 注意：scrollView 不在此处添加为子视图，由面板负责将其加入层级
  }
  
  // 必需的初始化器（从 Interface Builder 加载时使用）
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")  // 不支持从 Storyboard 创建
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

  // 当前滚动偏移（文档坐标 -> 可见坐标）
  var scrollOffset: NSPoint {
    return scrollView.contentView.bounds.origin
  }

  // 将 NSRange 转换为 NSTextRange 的工具函数
  // NSRange 是旧式的范围表示，NSTextRange 是新式的范围表示
  func convert(range: NSRange) -> NSTextRange? {
    guard range != .empty else { return nil }  // 如果是空范围，返回 nil
    
    // 计算起始位置
    guard let startLocation = textLayoutManager.location(textLayoutManager.documentRange.location, offsetBy: range.location) else { return nil }
    // 计算结束位置
    guard let endLocation = textLayoutManager.location(startLocation, offsetBy: range.length) else { return nil }
    // 创建并返回文本范围
    return NSTextRange(location: startLocation, end: endLocation)
  }

  // 获取包含整个内容的矩形区域，计算成本较高
  // 这个函数就像测量一张纸上所有文字占用的总面积
  var contentRect: NSRect {
    var ranges = candidateRanges  // 从候选字范围开始
    if preeditRange.length > 0 {
      ranges.append(preeditRange)  // 如果有预编辑文本，也加进来
    }
    
    // 初始化边界值，用于寻找最小和最大的坐标
    // swiftlint:disable:next identifier_name
    var x0 = CGFloat.infinity, x1 = -CGFloat.infinity, y0 = CGFloat.infinity, y1 = -CGFloat.infinity
    
    // 遍历所有范围，找出它们的边界
    for range in ranges {
      if let textRange = convert(range: range) {
        let rect = contentRect(range: textRange)  // 获取这个范围的矩形
        x0 = min(rect.minX, x0)  // 更新最小 x 坐标
        x1 = max(rect.maxX, x1)  // 更新最大 x 坐标
        y0 = min(rect.minY, y0)  // 更新最小 y 坐标
        y1 = max(rect.maxY, y1)  // 更新最大 y 坐标
      }
    }
    return NSRect(x: x0, y: y0, width: x1-x0, height: y1-y0)  // 返回包含所有内容的矩形
  }
  // 获取包含指定文本范围的矩形，计算成本较高
  // 这个函数会先转换为字形范围，然后计算矩形边界
  func contentRect(range: NSTextRange) -> NSRect {
    // 初始化边界值
    // swiftlint:disable:next identifier_name
    var x0 = CGFloat.infinity, x1 = -CGFloat.infinity, y0 = CGFloat.infinity, y1 = -CGFloat.infinity
    
    // 枚举文本段，计算每个段的矩形
    textLayoutManager.enumerateTextSegments(in: range, type: .standard, options: .rangeNotRequired) { _, rect, _, _ in
      var rect = rect
      rect.origin.x -= scrollOffset.x
      rect.origin.y -= scrollOffset.y
      x0 = min(rect.minX, x0)  // 更新边界
      x1 = max(rect.maxX, x1)
      y0 = min(rect.minY, y0)
      y1 = max(rect.maxY, y1)
      return true  // 继续枚举
    }
    return NSRect(x: x0, y: y0, width: x1-x0, height: y1-y0)  // 返回包含范围的矩形
  }

  // 触发视图重绘的函数，会调用 drawRect 方法
  // 这个函数更新视图的显示状态，就像给画家提供新的绘画信息
  // swiftlint:disable:next function_parameter_count
  func drawView(candidateRanges: [NSRange], hilightedIndex: Int, preeditRange: NSRange, highlightedPreeditRange: NSRange, canPageUp: Bool, canPageDown: Bool) {
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
    // 声明各种路径变量，用于绘制不同的形状
    var backgroundPath: CGPath?              // 背景路径
    var preeditPath: CGPath?                 // 预编辑文本背景路径
    var candidatePaths: CGMutablePath?       // 候选字背景路径
    var highlightedPath: CGMutablePath?      // 高亮候选字路径
    var highlightedPreeditPath: CGMutablePath?  // 高亮预编辑文本路径
    let theme = currentTheme                 // 获取当前主题

    // 计算包含区域，为翻页按钮留出空间
    var containingRect = dirtyRect
    containingRect.size.width -= theme.pagingOffset
    let backgroundRect = containingRect

    // 绘制预编辑文本矩形区域
    var preeditRect = NSRect.zero
    if preeditRange.length > 0, let preeditTextRange = convert(range: preeditRange) {
      // 计算预编辑文本的显示区域
      preeditRect = contentRect(range: preeditTextRange)
      preeditRect.size.width = backgroundRect.size.width  // 宽度占满背景区域
      // 调整高度，包含边距和行间距
      preeditRect.size.height += theme.edgeInset.height + theme.preeditLinespace / 2 + theme.hilitedCornerRadius / 2
      preeditRect.origin = backgroundRect.origin
      
      // 如果没有候选字，调整预编辑区域的高度
      if candidateRanges.count == 0 {
        preeditRect.size.height += theme.edgeInset.height - theme.preeditLinespace / 2 - theme.hilitedCornerRadius / 2
      }
      
      // 调整包含区域，为预编辑文本让出空间
      containingRect.size.height -= preeditRect.size.height
      containingRect.origin.y += preeditRect.size.height
      
      // 如果预编辑文本有背景颜色，创建背景路径
      if theme.preeditBackgroundColor != nil {
        preeditPath = drawSmoothLines(rectVertex(of: preeditRect), straightCorner: Set(), alpha: 0, beta: 0)
      }
    }

    containingRect = carveInset(rect: containingRect)  // 雕刻内边距
    
    // 绘制候选字矩形区域
    for i in 0..<candidateRanges.count {
      let candidate = candidateRanges[i]  // 获取当前候选字的范围
      
      if i == hilightedIndex {
        // 绘制高亮（选中）的候选字背景
        if candidate.length > 0 && theme.highlightedBackColor != nil {
          highlightedPath = drawPath(highlightedRange: candidate, backgroundRect: backgroundRect, preeditRect: preeditRect, containingRect: containingRect, extraExpansion: 0)?.mutableCopy()
        }
      } else {
        // 绘制其他候选字的背景
        if candidate.length > 0 && theme.candidateBackColor != nil {
          let candidatePath = drawPath(highlightedRange: candidate, backgroundRect: backgroundRect, preeditRect: preeditRect,
                                       containingRect: containingRect, extraExpansion: theme.surroundingExtraExpansion)
          // 如果候选字路径容器不存在，创建一个
          if candidatePaths == nil {
            candidatePaths = CGMutablePath()
          }
          // 将候选字路径添加到容器中
          if let candidatePath = candidatePath {
            candidatePaths?.addPath(candidatePath)
          }
        }
      }
    }

    // Draw highlighted part of preedit text
    if (highlightedPreeditRange.length > 0) && (theme.highlightedPreeditColor != nil), let highlightedPreeditTextRange = convert(range: highlightedPreeditRange) {
      var innerBox = preeditRect
      innerBox.size.width -= (theme.edgeInset.width + 1) * 2
      innerBox.origin.x += theme.edgeInset.width + 1
      innerBox.origin.y += theme.edgeInset.height + 1
      if candidateRanges.count == 0 {
        innerBox.size.height -= (theme.edgeInset.height + 1) * 2
      } else {
        innerBox.size.height -= theme.edgeInset.height + theme.preeditLinespace / 2 + theme.hilitedCornerRadius / 2 + 2
      }
      var outerBox = preeditRect
      outerBox.size.height -= max(0, theme.hilitedCornerRadius + theme.borderLineWidth)
      outerBox.size.width -= max(0, theme.hilitedCornerRadius + theme.borderLineWidth)
      outerBox.origin.x += max(0, theme.hilitedCornerRadius + theme.borderLineWidth) / 2
      outerBox.origin.y += max(0, theme.hilitedCornerRadius + theme.borderLineWidth) / 2

      let (leadingRect, bodyRect, trailingRect) = multilineRects(forRange: highlightedPreeditTextRange, extraSurounding: 0, bounds: outerBox)
      var (highlightedPoints, highlightedPoints2, rightCorners, rightCorners2) = linearMultilineFor(body: bodyRect, leading: leadingRect, trailing: trailingRect)

      containingRect = carveInset(rect: preeditRect)
      highlightedPoints = expand(vertex: highlightedPoints, innerBorder: innerBox, outerBorder: outerBox)
      rightCorners = removeCorner(highlightedPoints: highlightedPoints, rightCorners: rightCorners, containingRect: containingRect)
      highlightedPreeditPath = drawSmoothLines(highlightedPoints, straightCorner: rightCorners, alpha: 0.3 * theme.hilitedCornerRadius, beta: 1.4 * theme.hilitedCornerRadius)?.mutableCopy()
      if highlightedPoints2.count > 0 {
        highlightedPoints2 = expand(vertex: highlightedPoints2, innerBorder: innerBox, outerBorder: outerBox)
        rightCorners2 = removeCorner(highlightedPoints: highlightedPoints2, rightCorners: rightCorners2, containingRect: containingRect)
        let highlightedPreeditPath2 = drawSmoothLines(highlightedPoints2, straightCorner: rightCorners2, alpha: 0.3 * theme.hilitedCornerRadius, beta: 1.4 * theme.hilitedCornerRadius)
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
      }
      // 将候选字路径合并到主背景
      if let path = candidatePaths {
        backPath?.addPath(path)
      }
    }
    // 创建主面板图层，设置背景色，就像给画布涂上底色
    let panelLayer = shapeFromPath(path: backPath)
    panelLayer.fillColor = theme.backgroundColor.cgColor
    // 创建遮罩层，限制绘制范围在背景路径内，就像用模板控制绘画区域
    let panelLayerMask = shapeFromPath(path: backgroundPath)
    panelLayer.mask = panelLayerMask
    // 将主图层添加到视图中
  self.layer?.addSublayer(panelLayer)

    // 开始填充各种颜色和效果
    // 绘制输入预览区域的背景色
    if let color = theme.preeditBackgroundColor, let path = preeditPath {
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
      let layer = shapeFromPath(path: path)  // 创建候选字背景图层
      layer.fillColor = color.cgColor  // 设置候选字背景色
      panelLayer.addSublayer(layer)  // 添加到主图层
    }
    // 绘制被选中候选字的高亮背景（最重要的视觉反馈）
    if let color = theme.highlightedBackColor, let path = highlightedPath {
      let layer = shapeFromPath(path: path)  // 创建高亮图层
      layer.fillColor = color.cgColor  // 设置高亮背景色
      // 如果设置了阴影效果，添加阴影让高亮更突出
      if theme.shadowSize > 0 {
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
      }
      panelLayer.addSublayer(layer)  // 添加高亮图层到主图层
    }
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
      // 计算相对于文本视图的点击坐标，就像把全局坐标转换为局部坐标
      var point = NSPoint(x: clickPoint.x - textView.textContainerInset.width - currentTheme.pagingOffset,
                          y: clickPoint.y - textView.textContainerInset.height)
      // 加回滚动偏移以对齐文档坐标
      point.x += scrollView.contentView.bounds.origin.x
      point.y += scrollView.contentView.bounds.origin.y
      
      // 找到包含点击点的文本布局片段
      let fragment = textLayoutManager.textLayoutFragment(for: point)
      if let fragment = fragment {
        // 转换为片段内的相对坐标
        point = NSPoint(x: point.x - fragment.layoutFragmentFrame.minX,
                        y: point.y - fragment.layoutFragmentFrame.minY)
        // 计算在整个文档中的字符索引位置
        index = textLayoutManager.offset(from: textLayoutManager.documentRange.location, to: fragment.rangeInElement.location)
        
        // 遍历该片段中的每一行文本
        for lineFragment in fragment.textLineFragments where lineFragment.typographicBounds.contains(point) {
          // 转换为行内的相对坐标
          point = NSPoint(x: point.x - lineFragment.typographicBounds.minX,
                          y: point.y - lineFragment.typographicBounds.minY)
          // 获取在该行中的字符索引
          index += lineFragment.characterIndex(for: point)
          
          // 判断点击的是预编辑区域还是候选字区域
          if index >= preeditRange.location && index < preeditRange.upperBound {
            preeditIndex = index  // 点击了预编辑文本
          } else {
            // 检查是否点击了某个候选字
            for i in 0..<candidateRanges.count {
              let range = candidateRanges[i]
              if index >= range.location && index < range.upperBound {
                candidateIndex = i  // 找到被点击的候选字
                break
              }
            }
          }
          break  // 找到匹配的行后跳出循环
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
  func drawPath(highlightedRange: NSRange, backgroundRect: NSRect, preeditRect: NSRect, containingRect: NSRect, extraExpansion: Double) -> CGPath? {
    let theme = currentTheme        // 获取当前主题
    let resultingPath: CGMutablePath?  // 最终的绘制路径

    // 计算当前包含矩形，考虑额外扩展
    var currentContainingRect = containingRect
    currentContainingRect.size.width += extraExpansion * 2    // 宽度双向扩展
    currentContainingRect.size.height += extraExpansion * 2   // 高度双向扩展
    currentContainingRect.origin.x -= extraExpansion         // 向左扩展
    currentContainingRect.origin.y -= extraExpansion         // 向上扩展

    let halfLinespace = theme.linespace / 2  // 半行间距，用于精确定位

    // 计算内边界框，这是文本实际绘制的区域
    var innerBox = backgroundRect
    innerBox.size.width -= (theme.edgeInset.width + 1) * 2 - 2 * extraExpansion    // 扣除边距和扩展
    innerBox.origin.x += theme.edgeInset.width + 1 - extraExpansion                // 调整起始位置
    innerBox.size.height += 2 * extraExpansion                                     // 垂直方向扩展
    innerBox.origin.y -= extraExpansion                                            // 向下调整
    
    if preeditRange.length == 0 {
      // 没有预编辑文本时的调整
      innerBox.origin.y += theme.edgeInset.height + 1
      innerBox.size.height -= (theme.edgeInset.height + 1) * 2
    } else {
      // 有预编辑文本时需要为其留出空间
      innerBox.origin.y += preeditRect.size.height + theme.preeditLinespace / 2 + theme.hilitedCornerRadius / 2 + 1
      innerBox.size.height -= theme.edgeInset.height + preeditRect.size.height + theme.preeditLinespace / 2 + theme.hilitedCornerRadius / 2 + 2
    }
    innerBox.size.height -= theme.linespace  // 扣除行间距
    innerBox.origin.y += halfLinespace       // 调整垂直位置

    // 计算外边界框，这是高亮效果的最大范围
    var outerBox = backgroundRect
    outerBox.size.height -= preeditRect.size.height + max(0, theme.hilitedCornerRadius + theme.borderLineWidth) - 2 * extraExpansion
    outerBox.size.width -= max(0, theme.hilitedCornerRadius + theme.borderLineWidth) - 2 * extraExpansion
    outerBox.origin.x += max(0.0, theme.hilitedCornerRadius + theme.borderLineWidth) / 2.0 - extraExpansion
    outerBox.origin.y += preeditRect.size.height + max(0, theme.hilitedCornerRadius + theme.borderLineWidth) / 2 - extraExpansion

    // 计算有效的圆角半径，考虑扩展效果
    let effectiveRadius = max(0, theme.hilitedCornerRadius + 2 * extraExpansion / theme.hilitedCornerRadius * max(0, theme.cornerRadius - theme.hilitedCornerRadius))

    // 检查是否使用线性布局模式（支持多行高亮的复杂形状）
    if theme.linear, let highlightedTextRange = convert(range: highlightedRange) {
      // 线性布局：支持复杂的多行高亮形状，如L形、T形等
      let (leadingRect, bodyRect, trailingRect) = multilineRects(forRange: highlightedTextRange, extraSurounding: separatorWidth, bounds: outerBox)
      var (highlightedPoints, highlightedPoints2, rightCorners, rightCorners2) = linearMultilineFor(body: bodyRect, leading: leadingRect, trailing: trailingRect)

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
      if !nearEmpty(highlightedRect) {
        // 调整高亮矩形的尺寸和位置
        highlightedRect.size.width = backgroundRect.size.width  // 宽度占满背景
        highlightedRect.size.height += theme.linespace          // 增加行间距
        highlightedRect.origin = NSPoint(x: backgroundRect.origin.x, y: highlightedRect.origin.y + theme.edgeInset.height - halfLinespace)
        
        // 如果高亮到了文本末尾，额外增加底部空间
        if highlightedRange.upperBound == (textView.string as NSString).length {
          highlightedRect.size.height += theme.edgeInset.height - halfLinespace
        }
        
        // 如果高亮从文本开始位置开始，额外增加顶部空间
        if highlightedRange.location - (preeditRange == .empty ? 0 : preeditRange.upperBound) <= 1 {
          if preeditRange.length == 0 {
            // 没有预编辑文本时的调整
            highlightedRect.size.height += theme.edgeInset.height - halfLinespace
            highlightedRect.origin.y -= theme.edgeInset.height - halfLinespace
          } else {
            // 有预编辑文本时的调整
            highlightedRect.size.height += theme.hilitedCornerRadius / 2
            highlightedRect.origin.y -= theme.hilitedCornerRadius / 2
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
    return resultingPath  // 返回最终的绘制路径
  }

  // 雕刻内边距：从矩形中减去内边距和边框宽度，创建实际内容区域
  // 这个函数确保文本内容不会绘制到边框或圆角区域
  func carveInset(rect: NSRect) -> NSRect {
    var newRect = rect  // 复制原始矩形
    // 高度和宽度都要减去两倍的（圆角半径 + 边框宽度），因为上下左右都有
    newRect.size.height -= (currentTheme.hilitedCornerRadius + currentTheme.borderWidth) * 2
    newRect.size.width -= (currentTheme.hilitedCornerRadius + currentTheme.borderWidth) * 2
    // 起始位置要向内偏移（圆角半径 + 边框宽度）的距离
    newRect.origin.x += currentTheme.hilitedCornerRadius + currentTheme.borderWidth
    newRect.origin.y += currentTheme.hilitedCornerRadius + currentTheme.borderWidth
    return newRect  // 返回雕刻后的矩形
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
