<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [<2021-12-13 周一> 调试`libo-7.3`的`emf`流程（一）](#2021-12-13-周一-调试libo-73的emf流程一)
- [<2021-12-14 Tue> 调试`libo-7.3`的`emf`流程（二）](#2021-12-14-tue-调试libo-73的emf流程二)

<!-- markdown-toc end -->

| PLATFORM | COMMIT/BRANCH                            | BUILD TIEM |
| :-:      | :-:                                      |        :-: |
| WINDOWS  | 28d43b69651289dca7b62341726ae9771ba30e2c | 2021-11-16 |
| LINUX    | 79589afe173ba8f17bfbbc6b38f0dfbc5fd9e0c9 | 2021-11-13 |
| LINUX    | libreoffice-7-3                          | 2021-12-15 |

``` shellsession
# autogen.lastrun for windows
--with-ant-home=/cygdrive/d/cygwin64/home/user1328/sources/apache-ant-1.9.5
--with-jdk-home=/cygdrive/d/dnld/jdk-11.0.11+9
--enable-pch
--disable-ccache
--disable-odk
--disable-online-update
--without-junit
--enable-dbgutil

# autogen.lastrun for linux
--enable-dbgutil
```

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

# <2021-12-14 Tue> 调试`libo-7.3`的`emf`流程（二）

不知从哪里得到的启示，查看了`libo`关于“[Visual Class Library (VCL)](https://docs.libreoffice.org/vcl.html)”的说明文档，经过半天的尝试，感觉此时我获得了一点用的信息，所以赶紧记录一下。

搞了一个“[run_debug_libo_emf.sh](files/run_debug_libo_emf.sh)”，方便调试：

``` shell
#!/bin/bash

OUT=$HOME/temp/libo_emf.log

export SAL_LOG_FILE=$OUT

if [ -f $OUT ]; then
    rm -f $OUT
    printf "delete: %s\n" $OUT
fi

export SAL_LOG=\
+INFO.vcl\
-INFO.vcl.schedule\
-INFO.vcl.unity\
-INFO.vcl.virdev\
+INFO.emfio\
-INFO.vcl.opengl\
+INFO.drawinglayer.emf\
+WARN.vcl.emf

$HOME/libo_build/instdir/program/simpress
```

链接中提到用`export SAL_LOG=+INFO.cppcanvas.emf+INFO.vcl.emf`，发现没有相关日志输出，最终我换成了`+INFO.drawinglayer.emf`，发现有效果：

``` shellsession
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/wmfemfhelper.cxx:2978: EMF+ passed to canvas mtf renderer - header info, size: 56
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:979: EMF+ picture frame: 1322,1323 - 6400,2117
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:981: EMF+ ref device pixel size: 2560x1440 mm size: 677x381
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:983: EMF+ base transform: [1 0 0; 0 1 0; 0 0 1]
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/wmfemfhelper.cxx:3010: EMF+ passed to canvas mtf renderer, size: 28
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1076: EMF+ EmfPlusRecordTypeHeader (0x4001)
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1077: EMF+	 record size: 28
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1078: EMF+	 flags: 0x0
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1079: EMF+	 data size: 16
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1123: EMF+	Header: 0xdbc01002
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1124: EMF+	Version: 1
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1125: EMF+	Horizontal DPI: 96
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1126: EMF+	Vertical DPI: 96
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1127: EMF+	Dual: false
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/wmfemfhelper.cxx:3010: EMF+ passed to canvas mtf renderer, size: 132
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1076: EMF+ EmfPlusRecordTypeSetTextRenderingHint (0x401f)
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1077: EMF+	 record size: 12
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1078: EMF+	 flags: 0x4
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1079: EMF+	 data size: 0
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1771: EMF+	 Text rendering hint: TextRenderingHintSingleBitPerPixel
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1076: EMF+ EmfPlusRecordTypeObject (0x4008)
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1077: EMF+	 record size: 48
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1078: EMF+	 flags: 0x600
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1079: EMF+	 data size: 36
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:262: EMF+ Object: EmfPlusObjectTypeFont (0x1536)
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:263: EMF+	Object slot: 0
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:264: EMF+	Flags: 1536
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfpfont.cxx:52: EMF+	Header: 0xdbc01
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfpfont.cxx:53: EMF+	Version: 0x4098
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfpfont.cxx:54: EMF+	Size: 24
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfpfont.cxx:55: EMF+	Unit: UnitTypePixel (0x2)
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfpfont.cxx:56: EMF+	Flags:  (0x0)
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfpfont.cxx:57: EMF+	Reserved: 0x0
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfpfont.cxx:58: EMF+	Length: 5
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfpfont.cxx:72: EMF+	Family: ARIAL
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1076: EMF+ EmfPlusRecordTypeDrawString (0x401c)
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1077: EMF+	 record size: 72
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1078: EMF+	 flags: 0x8000
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1079: EMF+	 data size: 60
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1573: EMF+	 FontId: 0
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1574: EMF+	 BrushId: ARGB: 0x800000ff
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1575: EMF+	 FormatId: 4294967295
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1576: EMF+	 Length: 16
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1582: EMF+	 DrawString layoutRect: 50,50 - 0x0
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1585: EMF+	 DrawString string: Transparent Text
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/wmfemfhelper.cxx:3010: EMF+ passed to canvas mtf renderer, size: 12
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1076: EMF+ EmfPlusRecordTypeEndOfFile (0x4002)
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1077: EMF+	 record size: 12
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1078: EMF+	 flags: 0x0
info:drawinglayer.emf:43305:43305:drawinglayer/source/tools/emfphelperdata.cxx:1079: EMF+	 data size: 0
```
