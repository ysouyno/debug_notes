<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [<2021-08-31 周二> 调试`GM-1.3.35`的竖条纹问题（一）](#2021-08-31-周二-调试gm-1335的竖条纹问题一)
- [<2021-09-01 周三> 调试`GM-1.3.35`的竖条纹问题（二）](#2021-09-01-周三-调试gm-1335的竖条纹问题二)
- [<2021-09-02 周四> 调试`GM-1.3.35`的竖条纹问题（三）](#2021-09-02-周四-调试gm-1335的竖条纹问题三)
- [<2021-09-14 周二> 调试`GM-1.3.35`解析`bmp`成黑色图片问题（一）](#2021-09-14-周二-调试gm-1335解析bmp成黑色图片问题一)
- [<2021-09-15 周三> 调试`GM-1.3.35`解析`bmp`成黑色图片问题（二）](#2021-09-15-周三-调试gm-1335解析bmp成黑色图片问题二)
- [<2022-07-24 周日> 调试`GM-1.3.35`读`jpeg`图片效率低的问题（一）](#2022-07-24-周日-调试gm-1335读jpeg图片效率低的问题一)
- [<2022-07-25 周一> 调试`GM-1.3.35`读`jpeg`图片效率低的问题（二）](#2022-07-25-周一-调试gm-1335读jpeg图片效率低的问题二)

<!-- markdown-toc end -->

# <2021-08-31 周二> 调试`GM-1.3.35`的竖条纹问题（一）

目标文件就不上传了，文件太大，有`1.37M`，它是一张`png`的灰度图，大小为`2935x2148`。

``` emacs-lisp
(/ 180c9f0 1e0fc6b)
(/ 25217520.0 31521899)
(* 2935 2148 5)
(/ 26.0 18)
```

`WriteOnePNGImage`位于`png.c:6862`。

``` emacs-lisp
(- 31181 145)
(/ 31036 2935.0)
(- 31193 31181)
(/ (- 65705.0 145) 2935)
(/ (- 98485 65705) 2148.0)
(/ 11740.0 2935)
```

`ExportViewPixelArea`位于`export.c:3179`处获取的`pixels`的源数据就是错误的像素，即`view_info->nexus_info.pixels`的像素就是错误的。

# <2021-09-01 周三> 调试`GM-1.3.35`的竖条纹问题（二）

怎么获取`view_info`？见`export.c:278`

``` c++
AccessDefaultCcheView(image);

typedef void *ViewInfo;

MagickExport ViewInfo
*AccessDefaultCacheView(const Image *image)
{
  return (ViewInfo *) image->default_views->views[omp_get_thread_num()];
}
```

``` emacs-lisp
(/ 1446325.0 2935)
(/ 14675.0 2935)
```

似乎正确时获取的`pixels`的地址从`pixel_cache.c:671`返回，每次会增加，而错误时获取的`pixels`的地址一直不变，在`pixel_cahce.c:804`处计算，每次`region_pixels`的值不变，总是`2935`。

对于`pixel_cahce.c:804`处只有在竖条纹的图片时才会中断下来，而`pixel_cahce.c:800`处是所有走文件映射时会中断，错误的流程似乎是这样的：因为`pixels`的地址每次都不变，这样最后一行像素就是它的值，这是读图的过程，然而当读图完成后在`png.c:2663`执行`SyncImage(image);`时最终走到了`pixel_iterator.c:385`处去获取`pixels`时，每次也同样是相同的，因为获取`pixels`的地址仍然是`pixel_cahce.c:800`处的代码，然后进入`pixel_iterator.c:390`即`image.c:3700`的`SyncImageCallBack()`函数，这样，因为源`pixels`地址始终相同，且都为最后一行像素，这样得到的图片就变成竖条纹了。

上面分析得不对，进一步跟踪发现在`pixel_iterator.c:392`的`SyncImagePixelsEx(image, exception);`中向`TEMP`下写文件明明是对的，我保存了写了一半的临时文件与写完后的进行对比，发现开头的字节序已经不同了，说明在写完首次写完临时文件之后文件内容是正确的，但是后面谁对它进行了修改？

似乎将`png.c:2686`至`png.c:2752`之间的代码注释掉，竖条纹的问题没有出现了，调试发现在`png.c:2699`处的代码`q=SetImagePixels(image,0,y,image->columns,1);`返回的像素值都是以`9c`开头的，即图片的最后一行像素，这是错误的，再用此像素通过调用`pixel_cache.c:373`的`FilePositionWrite()`函数将原来正确的`TEMP`下的文件像素全部覆盖而导致竖条纹问题。

# <2021-09-02 周四> 调试`GM-1.3.35`的竖条纹问题（三）

调试步骤：先将断点设在`pixel_cache.c:804`行，当断下时说明此张图片将出现问题，禁用此断点，设置`png.c:2698`断点后继续运行，断下时返回的`pixels`即为错误数据（最后一行像素）

# <2021-09-14 周二> 调试`GM-1.3.35`解析`bmp`成黑色图片问题（一）

这里使用`GM-1.3.35`自带的`IMDisplay.exe`调试，因为此工具显示不了该图片。首先做了一些前期调查对于此张`bmp`图片：

1，此`bmp`文件大小为`45M`

2，宽高为：`2976x3968`（备注：通过自带的`画图`工具将其缩至`50%`后使用`gm`可以正常显示而不是之前的黑色图片

3，此`bmp`图片带有透明通道，`gm`是这么认为的，但是`im`却不认为它有透明通道，`im`显示该图片正确

读图的操作位于`IMDisplayDoc.cpp:108`的`BOOL CIMDisplayDoc::DoReadImage( void )`函数中，显示操作位于`IMDisplayView.cpp:767`的`void CIMDisplayView::DoDisplayImage( Image &inImage, CDC* pDC )`函数中。

对显示图片函数`CIMDisplayView::DoDisplayImage()`进行一些修改，这是在先前读图调试的基础上发现的，比如将`IMDisplayView.cpp:829`行的：

``` c++
if (inImage.matte())
{
  Magick::Image texture;
  texture.read("image:checkerboard");
  image.texture(texture);
  image.matte(false);
}
```

注释掉，则`gm`的`IMDisplay.exe`显示该图片正常，目前分析可知，`Magick::Image`类的`_imgRef`中`_image`结构体（类型为`MagickLib::Image`）中的`cache`成员（类型为`_CacheInfo`）中的`pixels`成员（类型为`PixelPacket`）存放的就是图片像素，当执行上述被注释掉的代码时，该`pixels`的地址被修改从而导致图片显示失败。

按此分析，只要用原图对象的`pixels`指针就能解决这个问题，但实际并非如此，我修改了`EImage.dll`中的代码，使其直接操作`pixels`指针，但是仍然能得到黑色图片，所以怀疑`Magick::Image`类的某些成员函数对于这种内存占用较大的的`bmp`图片会不经意间修改了`pixels`的地址，因此有如下尝试，仍保持上述代码注释：

``` c++
Magick::Image image=inImage;
/*if (inImage.matte())
{
  Magick::Image texture;
  texture.read("image:checkerboard");
  image.texture(texture);
  image.matte(false);
}*/
image.scale(Magick::Geometry(image.columns() / 2, image.rows() / 2));
```

则现在`IMDisplay.exe`显示成黑色图片了，但是将`scale`改为`sample`则图片可以显示（只不过显示的图片又有另外的问题：两张垂直方向缩放`50%`的该图片水平方向并列显示），刚好`EImage.dll`中用的就是`scale`这个缩放函数。

下午主要分析了`scale`缩放函数为什么产生黑色图片的问题，其实之前怀疑的`gm`图片解析错误是因为透明通道的问题导致，这是正确的，经过后面的验证，确实是因为透明的通道的问题，可以通过将`gm`的`bmp.c:984`处的代码：

``` c++
/*
  Image has alpha channel if alpha mask is specified, or is
  uncompressed and 32-bits per pixel
*/
image->matte=((bmp_info.alpha_mask != 0)
              || ((bmp_info.compression == BI_RGB)
                  && (bmp_info.bits_per_pixel == 32)));
```

修改为：

``` c++
image->matte=((bmp_info.alpha_mask != 0)
              && (bmp_info.compression == BI_BITFIELDS)) ? MagickTrue : MagickFail;
```

来解决！之前修改对了，但是发现解析出来的图片仍然是黑色的，真是让我百思不得其解。其实是因为编译时发生了一个低级错误，没有链接到修改后的`lib`文件上导致的，后来证实，只需要这么改就能修复。因为有了这个小小的错误从而有了下面进一步的尝试，我跟踪进了`resize.c:1685`处的`ScaleImage()`函数内部，看看究竟是哪里对像素进行了修改，发现在`resize.c:1817`处的：

``` c++
if (p->opacity == TransparentOpacity)
  {
    x_vector[x].red=0.0;
    x_vector[x].green=0.0;
    x_vector[x].blue=0.0;
  }
else
  {
    x_vector[x].red=p->red;
    x_vector[x].green=p->green;
    x_vector[x].blue=p->blue;
  }
```

和`resize.c:1850`处的：

``` c++
if (p->opacity == TransparentOpacity)
  {
    x_vector[x].red=0;
    x_vector[x].green=0;
    x_vector[x].blue=0;
  }
else
  {
    x_vector[x].red=p->red;
    x_vector[x].green=p->green;
    x_vector[x].blue=p->blue;
  }
```

对图片像素进行了赋值为`0`的操作，`0`即为黑色像素。我将`if`分支中的代码修改成`else`分支中一模一样的代码，发现图片不显示成黑色的了，而是像以前黑白电视上的雪花状，这明显是因为相差了一个`alpha`通道引起的，因此，我将上述修改`bmp.c:984`处的`image->matte`的代码更新上，图片就显示正确了。

因此还是透明通道的问题，且修改方法就是参考`im`的`bmp.c:889`处判断透明通道的方法：

``` c++
image->alpha_trait=((bmp_info.alpha_mask != 0) &&
  (bmp_info.compression == BI_BITFIELDS)) ? BlendPixelTrait :
  UndefinedPixelTrait;
```

因为`im`中判断是否含有透明通道是去检查`BlendPixelTrait`标记的，即`Image.cpp:321`的代码：

``` c++
bool Magick::Image::alpha(void) const
{
  if (constImage()->alpha_trait == BlendPixelTrait)
    return(true);
  else
    return(false);
}
```

注意`gm`中通过`Magick::Image::matte()`来判断图片是否含有透明通道，而`im`中通过`Magick::Image::alpha()`来判断。

现在还有最后一个问题，在本文开头的前期调查中提到：

> 2，宽高为：`2976x3968`（备注：通过自带的`画图`工具将其缩至`50%`后使用`gm`可以正常显示而不是之前的黑色图片

这又是为什么呢？原来通过`gm`提供的工具查看发现，`gm.exe identify -verbose xxx.bmp`发现，原图的输出中`Type`为：

```
...
Geometry: 2976x3968
...
Type: true color with transparency
...
```

经过`画图`工具缩放`50%`后的输出：

```
...
Geometry: 1488x1984
...
Type: true color
...
```

原来它的透明通道丢了，所以就显示正常了。

# <2021-09-15 周三> 调试`GM-1.3.35`解析`bmp`成黑色图片问题（二）

关于`bmp`的格式，看了中文维基上的公式写的`lisp`函数，调色板（即`Color table`）在小于`8`位深的`bmp`图片中肯定含有，因为之前的`bmp`是`DDB`，与设置相关，为了能达到显示效果图片自己就带上了调色板，而像`32`位的`bmp`则不需要，因为它们是`DIB`，通过下面的公式可以看出，`32`位再带上调色板，文件大小简直大得无法想象。

``` emacs-lisp
(defun calc_bmp_file_size_with_color_table (w h b)
  (+ 54 (* 4 (expt 2 b)) (/ (* w h b) 8)))

(defun calc_bmp_file_size(w h b)
  (+ 54 (/ (* w h b) 8)))

(calc_bmp_file_size_with_color_table 2976 3968 32)
(calc_bmp_file_size 2976 3968 32)
```

另经过测试，`bmp`获得`matte`的方法修改为：

``` c++
image->matte=((bmp_info.alpha_mask != 0)
              && (bmp_info.compression == BI_BITFIELDS)) ? MagickTrue : MagickFail;
```

用`gm`的`read`和`write`读完立即将文件写出来，发现虽然图片显示正常，但是图片属性从原来的`32`变成了`24`，显然这是将透明通道去掉了。不知道上面这么改以后会不会有什么问题？

经过半天开小差似的研究，`bmp`的图片结构、`BI_RGB`、`BI_BITFIELDS`、`24bpp`、`32bpp`的概念大概弄清楚了。先说`gm`的原始代码在判断图片是否含有透明通道的地方不妥，即`gm`的原代码是：

``` c++
/*
  Image has alpha channel if alpha mask is specified, or is
  uncompressed and 32-bits per pixel
*/
image->matte=((bmp_info.alpha_mask != 0)
              || ((bmp_info.compression == BI_RGB)
                  && (bmp_info.bits_per_pixel == 32)));
```

它将压缩为`BI_RGB`且位深度为`32`的图片都认为是带有透明通道的图片，然后在后续调用`scale`缩放图片时有代码如下：

``` c++
if (p->opacity == TransparentOpacity)
  {
    x_vector[x].red=0.0;
    x_vector[x].green=0.0;
    x_vector[x].blue=0.0;
  }
else
  {
    x_vector[x].red=p->red;
    x_vector[x].green=p->green;
    x_vector[x].blue=p->blue;
  }
```

即将透明通道处为`0xFF`（就是代码中的`TransparentOpacity`）的`RGB`像素的值都赋值为了黑色像素，因此我认为这是不妥的，我了解了`BI_RGB`的概念，参考：“[BI_RGB rgb pixel format](https://www.fourcc.org/pixel-format/rgb-bi_rgb/)”，发现`32bpp`是另一版本的`24bpp`，它只不过是为了使用上显卡加速而扩充成`u_int32`类型，那因此扩充出来的`alpha`通道当然全是`0xFF`即完全不透明，这样的`bmp`图片就是此次遇到的黑色图片，因此整个流程走通了。

且我下载了`opencv-4.5.3`的代码，在`grfmt_bmp.cpp:182`处有如下代码：

``` c++
// in 32 bit case alpha channel is used - so require CV_8UC4 type
m_type = iscolor ? (m_bpp == 32 ? CV_8UC4 : CV_8UC3 ) : CV_8UC1;
```

重点看此注释理解为：即在`32`位深度的`bmp`图片中仅表示它用到了`alpha`通道，而并不代表此图片是透明图片，因为它的透明值可能是完全不透明的`0xFF`。除非说`Magic::Image::matte()`的方法的含义就是表示它含有透明通道，而不是说它是透明图片，现在看来这是完全不同的两个概念。

因此上面`gm`的`ScaleImage()`中将`RGB`全部赋值为黑色是没有问题的。而关键问题就是判断`bmp`透明属性的问题。

此外尝试了该`bmp`图片使用`java.awt.image.ColorModel.hasAlpha()`方法获得是否透明的返回值为`0`，总结来看，除了`gm`觉得这张图片是透明的之外，其它如`java`，`im`（`opencv`没有这个透明属性）都不认为此`bmp`为透明图片，因此认为使用`im`的方法来判断更好，可以这么改：

``` c++
image->matte=((bmp_info.alpha_mask != 0)
              && (bmp_info.compression == BI_BITFIELDS)) ? MagickTrue : MagickFail;
```

即使用`BI_BITFIELDS`来判断`bmp`图片是否透明，另附：“[RGB pixel formats](https://www.fourcc.org/rgb.php)”，即：

| Lable         | FOURCC in Hex | Bits per pixel | Description                                                                                                                                                         |
| :-:           | :-:           | :-:            | :----------------------------------------------------------------------------------------------------------------------------------------                           |
| BI_BITFIELDS  | 0x00000003    | 16,24,32       | Raw RGB with arbitrary sample packing within a pixel. Packing and precision of R, G and B components is determined by bit masks for each.                           |
| BI_RGB        | 0x00000000    | 1,4,8,16,24,32 | Basic Windows bitmap format. 1, 4 and 8 bpp versions are palettised. 16, 24 and 32bpp contain raw RGB samples.                                                      |
| BI_RLE4       | 0x00000002    | 4              | Run length encoded 4bpp RGB image.                                                                                                                                  |
| BI_RLE8       | 0x00000001    | 8              | Run length encoded 8bpp RGB image.                                                                                                                                  |
| raw           | 0x32776173    | ?              | Apparently "raw, uncompressed RGB bitmaps" but I have no idea how many bits per pixel (uses bpp field in header?)                                                   |
| RGB(BI_RGB)   | 0x32424752    | 1,4,8,16,24,32 | Alias for BI_RGB                                                                                                                                                    |
| RGBA          | 0x41424752    | 16,32          | Raw RGB with alpha. Sample precision and packing is arbitrary and determined using bit masks for each component, as for BI_BITFIELDS.                               |
| RGBT          | 0x54424752    | 16,32          | Raw RGB with a transparency field. Layout is as for BI_RGB at 16 and 32 bits per pixel but the msb in each pixel indicates whether the pixel is transparent or not. |
| RLE(BI_RLE4)  | 0x34454C52    | 4              | Alias for BI_RLE4                                                                                                                                                   |
| RLE8(BI_RLE8) | 0x38454C52    | 8              | Alias for BI_RLE8                                                                                                                                                   |

# <2022-07-24 周日> 调试`GM-1.3.35`读`jpeg`图片效率低的问题（一）

调试发现在`coder/jpeg.c:ReadGenericProfile()`函数中调用了`AppendImageProfile()`函数，效率问题正出在此函数中，更具体的是`AppendImaeProfile()`函数中的`GetImageProfile()`函数。

在`GetImageProfile()`函数中会调用`MagickMapAccessEntry()`函数，然后调用`LocaleCompare()`对比`key`是否相等。为什么效率慢？见如下代码片断：

``` c++
/*
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%                                                                             %
%                                                                             %
%                                                                             %
+   M a g i c k M a p A c c e s s E n t r y                                   %
%                                                                             %
%                                                                             %
%                                                                             %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%  MagickMapAccessEntry() searches for an object in the map identified
%  by the specified key. If a matching object is found, then a const
%  pointer to the object data is returned, and the object_size
%  argument is updated with the object size. Null is returned if no
%  matching object is found.
%
%  An object is not required to contain a size so object_size may be
%  updated to zero. If the object size is known to not be required by
%  this object type, then a null object_size pointer may be passed.
%
%  The format of the MagickMapAccessEntry method is:
%
%      const void *MagickMapAccessEntry(MagickMap map,const char *key,
%                                       size_t *object_size)
%
%  A description of each parameter follows:
%
%    o map: map context
%
%    o key: unique key to match
%
%    o object_size: Pointer to where object size is to be saved.
%
*/
MagickExport const void *
MagickMapAccessEntry(MagickMap map,const char *key, size_t *object_size)
{
  MagickMapObject
    *p;

  assert(map != 0);
  assert(map->signature == MagickSignature);
  assert(key != 0);

  if (object_size)
    *object_size=0;

  (void) LockSemaphoreInfo(map->semaphore);

  for (p=map->list; p != 0; p=p->next)
    if (LocaleCompare(key,p->key) == 0)
      {
        if (object_size)
          *object_size=p->object_size;
        (void) UnlockSemaphoreInfo(map->semaphore);
        return(p->object);
      }

  (void) UnlockSemaphoreInfo(map->semaphore);

  return 0;
}
```

我的分析是这样的，`MagickMapAccessEntry()`函数内部首先要在`map`中遍历`key`，得到的`key`（长度为`4`）还要和目标`key`再进行一个字符一个字符的比较，因此效率大打折扣。

# <2022-07-25 周一> 调试`GM-1.3.35`读`jpeg`图片效率低的问题（二）

上面的分析“[<2022-07-24 周日> 调试`GM-1.3.35`读`jpeg`图片效率低的问题（一）](#2022-07-24-周日-调试gm-1335读jpeg图片效率低的问题一)”是错误的，几个循环就能把效率变得这么差？

按照`1.3.38`的思路，我准备自己动手实现一下，首先在内存里开辟一块空间，这里借用`ErrorManager`结构体的空间，然后先保存到这块内存，最后在`ReadJPEGImage()`函数运行时再将它全部存到`image`中，所以我的代码有：

``` c++
typedef struct _ErrorManager
{
  Image
    *image;

  MagickBool
    ping;

  MagickBool
    completed;

  jmp_buf
    error_recovery;

  unsigned int
    max_warning_count;

  magick_uint16_t
    warning_counts[JMSG_LASTMSGCODE];

  int
    max_scan_number;

  ProfileInfo
    *profiles;

  int
    profiles_len;

  unsigned char
    buffer[65537+200];

} ErrorManager;
```

``` c++
boolean append_profile_to_error_manager(ErrorManager *em, const char *name,
                                        const unsigned char *profile_data,
                                        const size_t data_len) {
  int i = 0;

  // if `name` found, append data
  for (i = 0; i < em->profiles_len; ++i) {
    ProfileInfo *p = &em->profiles[i];
    if (!p->name)
      break;

    if (0 == strcmp(p->name, name)) {
      int new_len = p->length + data_len;
      MagickReallocMemory(unsigned char *, p->info, new_len);
      if (p->info) {
        memcpy(p->info + p->length, profile_data, data_len);
        p->length = new_len;
        return True;
      }
    }
  }

  // if `name` not found, add data
  for (i = 0; i < em->profiles_len; ++i) {
    ProfileInfo *p = &em->profiles[i];
    if (p->name)
      continue;

    p->name = AcquireString(name);
    MagickReallocMemory(unsigned char *, p->info, data_len);
    if (!p->info) {
      MagickFreeMemory(p->name);
      MagickFreeMemory(p->info);
      break;
    }

    memcpy(p->info, profile_data, data_len);
    p->length = data_len;
    return True;
  }

  return False;
}

void init_error_manager_profiles(ErrorManager *em) {
  if (!em)
    return;

  em->profiles_len = 16;
  MagickReallocMemory(ProfileInfo *, em->profiles,
                      em->profiles_len * sizeof(ProfileInfo));
  memset(em->profiles, 0, em->profiles_len * sizeof(ProfileInfo));
}

void free_error_manager_profiles(ErrorManager *em) {
  int i = 0;

  if (!em)
    return;

  for (i = 0; i < em->profiles_len; ++i) {
    ProfileInfo *p = &em->profiles[i];
    MagickFreeMemory(p->name);
    MagickFreeMemory(p->info);
  }

  MagickFreeMemory(em->profiles);
}
```

然后在`ReadGenericProfile()`函数中替换`AppendImageProfile()`

``` c++
/*
  Store profile in Image.
*/
/* (void) AppendImageProfile(image,profile_name,profile+header_length, */
/*                           length-header_length); */
append_profile_to_error_manager(error_manager,
                                profile_name,
                                profile+header_length,
                                length-header_length);
```

最后`init_error_manager_profiles()`和`free_error_manager_profiles()`函数放到`ReadJPEGImage()`函数中调用即可，代码不贴了。测试一下效果发现性能提高了大概将近一半。但是处理时间仍然在二十秒左右，这个时间还是太长。

所以我又研究了一下，发现性能的损失是由于`realloc()`函数被频繁调用导致内存的频繁拷贝，那为什么同样的思路`1.3.38`却没有这个问题呢？它的整个处理时间只有一两秒，这是为什么？

最后发现是在申请内存时`1.3.38`中为了减少`realloc()`的调用次数，使用了：

``` c++
/*
  Compute a value which is the next kilobyte power of 2 larger than
  the requested value or 256 whichever is larger.

  The objective is to round up the size quickly (and in repeatable
  steps) in order to reduce the number of memory copies due to realloc
  for strings which grow rapidly, while producing a reasonable size
  for smaller strings.
*/
#define MagickRoundUpStringLength(size)                                 \
  do {                                                                  \
    size_t                                                              \
      _rounded,                                                         \
      _target;                                                          \
                                                                        \
    _target=(Max(size,256));                                            \
    for (_rounded=256U; _rounded < _target; _rounded *= 2);             \
    size=_rounded;                                                      \
} while(0)
```

同时需要配合`magick/memory.c`的`_MagickReallocateResourceLimitedMemory()`函数，需要记录各内存长度变量等等，如果将`_MagickReallocateResourceLimitedMemory()`中的`MagickRoundUpStringLength()`注释掉，则时间也变成了和`1.3.35`一样，变成三十几秒。

看来什么东西都要自己亲手尝试一下才能有所体会。
