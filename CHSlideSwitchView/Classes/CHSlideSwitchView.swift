//
//  CHSlideSwitchView.swift
//  Pods
//
//  Created by Chance on 2017/6/2.
//
//

import UIKit
import SnapKit


/// 滑动时加载新视图的时机
///
/// - normal: 滑动或者动画结束
/// - scale: 根据设置滑动百分比添加0-1
public enum CHSlideLoadViewTiming {
    
    case normal
    case scale(Float)
    
    
}
//重写相等处理
public func ==(lhs: CHSlideLoadViewTiming, rhs: CHSlideLoadViewTiming) -> Bool {
    switch (lhs,rhs) {
    case (.normal,.normal) : return true
    case let (.scale(i), .scale(j)) where i == j: return true
    default: return false
    }
}

/// 滑动视图组件
open class CHSlideSwitchView: UIView {
    
    /// 顶部的标签栏
    @IBOutlet public var headerView: CHSlideHeaderView? {
        didSet {
            self.headerView?.slideSwitchView = self
        }
    }
    
    /// 是否集成顶部标签栏视图
    @IBInspectable open var isIntegrateHeaderView: Bool = true
    
    /// 主视图
    public var rootScrollView: UIScrollView!
    
    /// 内容元素组
    open var slideItems: [CHSlideItem] = [CHSlideItem]() {
        didSet {
            self.setNeedsLayout()
        }
    }
    
    /// 初始化显示页签位置
    open var showIndex: Int = 0
    
    /// 缓存的页面个数，越大使用内存越多
    open var cacheSize: Int = 4
    
    /// 缓存页面对象，最大数量为cacheSize值
    open var viewsCache = [Int: AnyObject]()
    
    /// 代理
    public weak var delegate: CHSlideSwitchViewDelegate? {
        didSet {
            //关闭UIViewController自动调整scrollInsets
            self.parent?.automaticallyAdjustsScrollViewInsets = false
        }
    }
    
    /// 是否全部视图加载
    open var loadAll: Bool = false
    
    /// 加载新视图的时机，默认动画结束时加载
    open var loadViewTiming: CHSlideLoadViewTiming = .normal
    
    /// 滚动起始的x位置
    var startOffsetX: CGFloat = 0
    
    /// 顶部标签栏高度
    var heightOfHeaderView: CGFloat {
        let base: CGFloat = 35  //默认35
        return self.delegate?.heightOfSlideHeaderView(view: self) ?? base
    }
    
    
    /// 父级控制器
    var parent: UIViewController? {
        return self.delegate as? UIViewController
    }

    
    /// 内容的高度
    var scrollHeight: CGFloat {
        return self.height - self.heightOfHeaderView
    }
    
    
    /// 当前页面位置
    fileprivate var currentIndex: Int = -1 {
        didSet {
            if oldValue != self.currentIndex {
                self.headerView?.selectedTabView(at: self.currentIndex)
            }
        }
    }
    
    // MARK: - 初始化方法
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.createUI()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        //如果你通过在XIB中设置初始化值，不要在这里做子视图的初始化，而是通过awakeFromNib
    }
    
    open override func awakeFromNib() {
        super.awakeFromNib()
        self.createUI()
    }
    
    // MARK: - 内部方法
    
    /// 创建UI
    func createUI() {
        
        var rootViewOffetY: CGFloat = 0
        
        // 顶部View没有绑定XIB，而且需求显示Tab，就进行创建
        if self.isIntegrateHeaderView {
            self.headerView = CHSlideHeaderView()
            self.headerView?.slideSwitchView = self
            self.addSubview(self.headerView!)
            
            //设置布局
            self.headerView!.snp.makeConstraints { (make) -> Void in
                make.height.equalTo(self.heightOfHeaderView)
                make.left.right.equalToSuperview().offset(0)
                make.top.equalToSuperview().offset(0)
            }
            
            rootViewOffetY = self.heightOfHeaderView
        }
        
        // 创建滚动主视图
        self.rootScrollView = UIScrollView()
        self.addSubview(self.rootScrollView)
        
        self.rootScrollView.backgroundColor = UIColor.white
        self.rootScrollView.delegate = self
        self.rootScrollView.isPagingEnabled = true
        self.rootScrollView.isUserInteractionEnabled = true
        self.rootScrollView.bounces = false
        self.rootScrollView.showsHorizontalScrollIndicator = false
        self.rootScrollView.showsVerticalScrollIndicator = false
        
        self.rootScrollView.panGestureRecognizer.addTarget(self, action: #selector(self.scrollHandlePan(pan:)))
        
        //设置布局
        self.rootScrollView.snp.makeConstraints { (make) in
            make.top.equalToSuperview().offset(rootViewOffetY)
            make.left.right.equalToSuperview().offset(0)
            make.bottom.equalToSuperview().offset(0)
        }
        
        
        
    }
    
    
    /// 重载布局
    open override func layoutSubviews() {
        super.layoutSubviews()
        self.layoutContentView()
    }
    
    /// 创建内容视图UI
    open func layoutContentView() {
        
        /// 设置数据源
        let viewCount = self.setDataSources()
        
        self.rootScrollView.contentSize = CGSize(width: CGFloat(viewCount) * self.width, height: self.scrollHeight)
        
        //是否加载全部页面
        if !self.loadAll && viewCount > 0 {
            //只加载显示的当前页面
            self.setContentOffset(index: self.showIndex, animated: false)
            
        }
        
        self.headerView?.isSelectTab = false
    }
    
    
    /// 重新加载数据
    open func reloadData() {
        
        //刷新子视图布局
        self.setNeedsLayout()
        
    }
    
    /// 获取数据源
    ///
    /// - Returns:
    open func setDataSources() -> Int {
        
        let viewCount = self.slideItems.count
        
        //父级视图遇到大调整，清除所有子视图，如：横竖屏切换
        for i in 0..<self.viewsCache.count {
            self.removeViewCacheIndex(index: i)
        }
        
        if viewCount > 0 {
            
            //如果缓存数量比加载的页面多，缓存修改为页面最大数
            if self.cacheSize > viewCount {
                self.cacheSize = viewCount
            }
            
            self.showIndex = min(viewCount - 1, max(0, self.showIndex))
            
            var startIndex = 0
            
            //是否加载全部页面
            if self.loadAll {
                if viewCount - self.showIndex > self.cacheSize {
                    //缓存不足从起始位加载全部，从起始位开始加载
                    startIndex = showIndex
                } else {
                    //缓存足够从起始位加载全部，计算一个比起始位加载更多页面的位置
                    startIndex = viewCount - self.cacheSize
                }
                
                //加载页面到缓存
                for i in startIndex..<startIndex + self.cacheSize {
                    _ = self.addViewCacheIndex(index: i)
                }
                
            }
            
            //更新头部
            self.headerView?.slideItems = self.slideItems
            self.headerView?.reloadTabs()
            
        }
        
        return viewCount
    }
    
    
    
    /// 添加视图到缓存组仲
    ///
    /// - Parameter index: 页签索引
    /// - Returns: 是否重新添加，true：重新添加，false：已经存在
    open func addViewCacheIndex(index: Int) -> Bool {
        
        var targetView: UIView?
        var flag = false
        
        //如果找不到缓存则重试初始化，并掺入
        if !self.viewsCache.keys.contains(index) {
            
            let item = self.slideItems[index]
            let obj = item.content.entity
            self.viewsCache[index] = obj
            switch obj {
            case let view as UIView:
                targetView = view
                self.rootScrollView.addSubview(view)
            case let vc as UIViewController:
                targetView = vc.view
                self.rootScrollView.addSubview(vc.view)
                if let parent = self.parent {
                    parent.addChildViewController(vc)
                }
            default:break
            }
            
            targetView?.frame = CGRect(x: CGFloat(index) * self.width, y: 0, width: self.width, height: self.height)
            
            //删除最远处的缓存对象
            if self.viewsCache.count > self.cacheSize {
                var removeIndex = index  - self.cacheSize
                //检查是否溢出
                if removeIndex < 0 {
                    removeIndex = index + self.cacheSize
                }
                
                self.removeViewCacheIndex(index: removeIndex)
                
            }
            
            flag = true
        } else {
            
            flag = false
        }
        

        return flag
    }
    
    
    /// 移除缓存组中View
    ///
    /// - Parameter index: 页签索引
    open func removeViewCacheIndex(index: Int) {
        let obj = self.viewsCache.removeValue(forKey: index)
        
        switch obj {
        case let view as UIView:
            view.removeFromSuperview()
        case let vc as UIViewController:
            vc.view.removeFromSuperview()
            vc.removeFromParentViewController()
        default:break
        }
    }
    
}

extension CHSlideSwitchView: UIScrollViewDelegate {
    
    
    func scrollHandlePan(pan: UIPanGestureRecognizer) {
        
    }
    
    
    /// 代码执行滚动视图
    ///
    /// - Parameters:
    ///   - index: 位置
    ///   - animated:   是否执行动画
    public func setContentOffset(index: Int, animated: Bool) {
        if self.showIndex >= 0 {
            let point = CGPoint(x: CGFloat(index) * self.rootScrollView.width, y: 0)
            self.setContentOffset(point, animated: true)
        }
    }
    
    
    /// 代码执行滚动视图
    ///
    /// - Parameters:
    ///   - contentOffset: 偏移坐标
    ///   - animated: 是否执行动画
    public func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        self.rootScrollView.setContentOffset(contentOffset, animated: animated)
        
        //计算偏移到哪一页
        self.currentIndex = Int(contentOffset.x / self.width)
        _ = self.addViewCacheIndex(index: self.currentIndex)
        
    }
    
    
    /// 滑动开始
    ///
    /// - Parameter scrollView:
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        self.startOffsetX = scrollView.contentOffset.x
    }
    
    
    /// 滑动过程回调
    ///
    /// - Parameter scrollView:
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let scale = self.rootScrollView.contentOffset.x / self.rootScrollView.contentSize.width
        self.headerView?.changePointScale(scale: scale)
    }
    
    
    /// 滑动后释放
    ///
    /// - Parameter scrollView:
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        //计算偏移到哪一页
        self.currentIndex = Int(scrollView.contentOffset.x / self.width)
        if self.loadViewTiming == .normal {
            _ = self.addViewCacheIndex(index: self.currentIndex)
        }
        self.headerView?.isSelectTab = false
    }
    
    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        
        self.headerView?.isSelectTab = false
    }
}
