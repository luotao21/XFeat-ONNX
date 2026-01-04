## XFeat-ONNX：用于轻量级图像匹配的 ONNX 加速特征

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![ONNX](https://img.shields.io/badge/ONNX-grey)](https://onnx.ai/)

### [[ArXiv]](https://arxiv.org/abs/2404.19174) | [[项目页面]](https://www.verlab.dcc.ufmg.br/descriptors/xfeat_cvpr24/) |  [[CVPR'24 论文]](https://cvpr.thecvf.com/)

[XFeat: Accelerated Features for Lightweight Image Matching](https://github.com/verlab/accelerated_features/tree/main) 的 Open Neural Network Exchange (ONNX) 兼容实现。ONNX 模型格式允许在支持多个执行提供程序的各种平台上进行互操作，并消除了对 PyTorch 等特定于 Python 的依赖。

本项目还提供了 C++ 源代码来测试模型！

## 目录

- [安装](#安装)
- [用法](#用法)
  - [推理](#推理)
- [注意事项](#注意事项)
- [引用](#引用)
- [许可](#许可)
- [致谢](#致谢)

## 安装

TODO 或使用 Pip 安装某些内容。

## 用法

### 推理

TODO

## 注意事项

由于 ONNX Runtime 对动态控制流等特性的支持有限，模型的某些配置无法轻易导出到 ONNX。这些注意事项概述如下。

### 特征提取

- 目前仅支持批大小 (batch size) 为 `1`。这一限制源于同一批次中的不同图像可能具有不同数量的关键点，从而导致非均匀（即 *ragged*）张量。
因此，代码与原始项目有所不同：移除了批处理操作。

### 多尺度

- 目前不支持 Dense Multiscale 模型。这可能是未来的工作方向！

### 关键点位置

- ~~为了比较 Pytorch/Onnx/C++ 模型，使用了 assets 文件夹中的图像。从结果中可以看出，Python Pytorch/ONNX 的结果非常相似。对于 C++ 部分，结果可能会略有不同，特别是与 Python 版本相比，点位会有明显的向上偏移。然而，当使用未应用填充 (padding) 的图像 (image_800x608) 时，不会发生偏移。是否在某些地方丢失了缩放/舍入因子？~~
--> 请注意绘制关键点函数的 float/int 类型问题。

## 引用

项目取自：[XFeat](https://github.com/verlab/accelerated_features/tree/main)

请引用论文：

```bibtex
@INPROCEEDINGS{potje2024cvpr,
  author={Guilherme {Potje} and Felipe {Cadar} and Andre {Araujo} and Renato {Martins} and Erickson R. {Nascimento}},
  booktitle={2024 IEEE / CVF Computer Vision and Pattern Recognition (CVPR)}, 
  title={XFeat: Accelerated Features for Lightweight Image Matching}, 
  year={2024}}
```

## 许可

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

## 致谢

感谢你们出色的工作！
[Guilherme Potje](https://guipotje.github.io/) · [Felipe Cadar](https://eucadar.com/) · [Andre Araujo](https://andrefaraujo.github.io/) · [Renato Martins](https://renatojmsdh.github.io/) · [Erickson R. Nascimento](https://homepages.dcc.ufmg.br/~erickson/)
