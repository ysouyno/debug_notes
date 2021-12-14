<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [<2021-12-13 周一> 调试`libo-7.3`的`emf`流程（一）](#2021-12-13-周一-调试libo-73的emf流程一)

<!-- markdown-toc end -->

# <2021-12-13 周一> 调试`libo-7.3`的`emf`流程（一）

在`XEmfParser::getDecomposition()`函数中，当读取`emf`文件结束后会调用：

``` c++
// xemfparser.cxx

// ...and create a single MetafilePrimitive2D containing the Metafile.
// CAUTION: Currently, ReadWindowMetafile uses the local VectorGraphicData
// and a MetafileAccessor hook at the MetafilePrimitive2D inside of
// ImpGraphic::ImplGetGDIMetaFile to get the Metafile. Thus, the first
// and only primitive in this case *has to be* a MetafilePrimitive2D.
aRetval.push_back(
    new drawinglayer::primitive2d::MetafilePrimitive2D(
        aMetafileTransform,
        aMtf));
```

此处的代码我觉得比较重要，因为从我目前分析到的流程来看，最终解析出的`emf`信息将会在`SdrPaintView::CompleteRedraw()`函数中通过`BeginCompleteRedraw()`，`DoCompleteRedraw()`和`EndCompleteRedraw()`函数来进行绘制，先看这里的`aRetval`是：

``` c++
class SAL_WARN_UNUSED DRAWINGLAYER_DLLPUBLIC Primitive2DContainer final
    : public std::deque<Primitive2DReference>,
      public Primitive2DDecompositionVisitor
{}

drawinglayer::primitive2d::Primitive2DContainer aRetval;
```

即`aRetval`就是一个`std::deque<Primitive2DReference>`，它的成员都是`Primitive2DReference`类型，这个类型其实就是一个基类指针类型，我看了半天才理清关系。首先看`Primitive2DReference`的定义，它其实就是一个`css::graphic::XPrimitive2D`类型：

``` c++
// CommonTypes.hxx

namespace drawinglayer::primitive2d
{
typedef css::uno::Reference<css::graphic::XPrimitive2D> Primitive2DReference;
typedef css::uno::Sequence<Primitive2DReference> Primitive2DSequence;
} // end of namespace drawinglayer::primitive2d
```

那为什么`aRetval`可以将`MetafilePrimitive2D`类型推进去呢？因为`MetafilePrimitive2D`继承自`BufferedDecompositionPrimitive2D`继承自`BasePrimitive2D`继承自`BasePrimitive2DImplBase`继承自`css::graphic::XPrimitive2D`。

现在再看：

``` c++
void SdrPaintView::DoCompleteRedraw(SdrPaintWindow& rPaintWindow, const vcl::Region& rReg, sdr::contact::ViewObjectContactRedirector* pRedirector)
{
    // redraw all PageViews with the target. This may expand the RedrawRegion
    // at the PaintWindow, plus taking care of FormLayer expansion
    if(mpPageView)
    {
        mpPageView->CompleteRedraw(rPaintWindow, rReg, pRedirector);
    }
}
```

注意上面的第三个参数`ViewObjectContactRedirector`：

``` c++
// viewobjectcontactredirector.hxx

// This class provides a mechanism to redirect the paint mechanism for all or
// single ViewObjectContacts. An own derivation may be set at single ViewContacts
// or at the ObjectContact for redirecting all. If both is used, the one at single
// objects will have priority.
class SVXCORE_DLLPUBLIC ViewObjectContactRedirector
{
public:
    // basic constructor.
    ViewObjectContactRedirector();

    // The destructor.
    virtual ~ViewObjectContactRedirector();

    // all default implementations just call the same methods at the original. To do something
    // different, override the method and at least do what the method does.
    virtual drawinglayer::primitive2d::Primitive2DContainer createRedirectedPrimitive2DSequence(
        const sdr::contact::ViewObjectContact& rOriginal,
        const sdr::contact::DisplayInfo& rDisplayInfo);
};
```

看到它的最后一个虚函数`createRedirectedPrimitive2DSequence()`的返回值是`drawinglayer::primitive2d::Primitive2DContainer`，这样暂时就把上面解析`emf`和这里绘制的代码结合起来了。
