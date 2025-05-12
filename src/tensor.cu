#pragma once

#include <cmath>
#include <iostream>
#include <memory>
#include <vector>

#include "constant.h"
#include "tensor.h"

template <typename T>
ushionn::Tensor::Tensor(std::initializer_list<size_t> shapes, const std::vector<T>& data)
    : dtype_(TypeToEnum<T>::value),
      shape_(shape),
      data_(new T[data.size()]),
      data_size_(data.size()),
      shape_size_(shapes.size())
{
    std::copy(data.begin(), data.end(), static_cast<T*>(data_.get()));
}

void ushionn::Tensor::CUDA()
{
    if (device_ == Device::CUDA) return;
    void* ptr = nullptr;

    cudaMalloc(&ptr, data_size_ * GetDTypeSize());
    auto err_code = cudaMemcpy(ptr, data_.get(), data_size_ * GetDTypeSize(), cudaMemcpyHostToDevice);
    device_ = Device::CUDA;

    if (err_code != cudaSuccess)
    {
        std::cerr << "Error : failed to copy Tensor from host to device, Error Code : " << err_code << std::endl;
        cudaFree(ptr);
    }
    else
    {
        data_.reset(ptr);
    }
}

void ushionn::Tensor::CPU()
{
    if (device_ == Device::CPU) return;
    void* ptr = nullptr;

    AllocCPUArray(ptr, data_size_);
    auto err_code = cudaMemcpy(ptr, data_.get(), data_size_ * GetDTypeSize(), cudaMemcpyDeviceToHost);
    device_ = Device::CPU;

    if (err_code != cudaSuccess)
    {
        std::cerr << "Error : failed to copy Tensor from device to host, Error Code : " << err_code << std::endl;
    }
    else
    {
        cudaFree(data_.get());
        data_.release();
        data_.reset(ptr);
    }
}

ushionn::Device ushionn::Tensor::GetDevice() const
{
    return device_;
}

template <typename T>
T ushionn::Tensor::Index(std::initializer_list<size_t> indexList)
{
    std::vector<size_t> tmp(indexList);
    if (tmp.size() != shapeSize_)
    {
        std::cerr << "Error : Given index list do not match dimension size" << std::endl;
        throw "given index list do not match dimension size";
    }

    int idx = 0;

    for (int i = 0; i < shapeSize_; ++i)
    {
        int multiple = 1;
        for (int j = shapeSize_ - 1; j > i; --j) multiple *= shape_[j];
        idx += tmp[i] * multiple;
    }

    return data_.get()[idx];
}

bool ushionn::Tensor::SetDims(std::initializer_list<size_t> dimList)
{
    std::vector<size_t> tmp(dimList);
    int size = 1;
    for (const auto& dim : tmp) size *= dim;
    if (size != shape_size_) return false;
    shape_.assign(dimList);
    shape_size_ = tmp.size();
    return true;
}

size_t ushionn::Tensor::GetDTypeSize()
{
    if (dtype_ == DataType::FLOAT32)
        return sizeof(float);
    else if (dtype_ == DataType::FLOAT64)
        return sizeof(double);
    else if (dtype_ == DataType::INT32)
        return sizeof(int);
}

void ushionn::Tensor::AllocCPUArray(void* ptr, size_t size)
{
    if (dtype_ == DataType::FLOAT32)
        ptr = new float[size];
    else if (dtype_ == DataType::FLOAT64)
        ptr = new double[size];
    else if (dtype_ == DataType::INT32)
        ptr = new int[size];
}

#ifdef USE_CUDNN
#else  // #TODO 나중에 수정
template <typename T, typename S>
__global__ void MultiplyCUDA1D(const T* src, const S target, T* out, const size_t dimX)
{
    const int tid = Grid1DTID(blockIdx.x, threadIdx.x, threadIdx.y, threadIdx.z);
    const size_t tDimX = GDim_X * blockIdx.x + threadIdx.x;
    if (tDimX >= dimX) return;
    out[tid] = src[tid] * target;
}

template <typename T, typename S>
__global__ void MultiplyCUDA2D(const T* src, const S target, T* out, const size_t dimX, const size_t dimY)
{
    const int tid = Grid2DTID(blockIdx.x, blockIdx.y, threadIdx.x, threadIdx.y, threadIdx.z);
    const int tDimY = GDim_Y * blockIdx.y + threadIdx.y;
    const int tDimX = GDim_X * blockIdx.x + threadIdx.x;
    if (tDimX >= dimX || tDimY >= dimY) return;
    out[tid] = src[tid] * target;
}

template <typename T, typename S>
__global__ void MultiplyCUDA3D(const T* src, const S target, T* out, const size_t dimX, const size_t dimY,
                               const size_t dimZ)
{
    const int tid = Grid3DTID(blockIdx.x, blockIdx.y, blockIdx.z, threadIdx.x, threadIdx.y, threadIdx.z);
    const size_t tDimZ = GDim_Z * blockIdx.z + threadIdx.z;
    const size_t tDimY = GDim_Y * blockIdx.y + threadIdx.y;
    const size_t tDimX = GDim_X * blockIdx.x + threadIdx.x;

    if (tDimX >= dimX || tDimY >= dimY || tDimZ >= dimZ) return;
    out[tid] = src[tid] * target;
}

template <typename T>
__global__ void AddCUDA1D(const T* src, const T* target, T* out, const size_t dimX)
{
    const int tid = Grid1DTID(blockIdx.x, threadIdx.x, threadIdx.y, threadIdx.z);
    const size_t tDimX = GDim_X * blockIdx.x + threadIdx.x;
    if (tDimX >= dimX) return;
    out[tid] = src[tid] + target[tid];
}

template <typename T>
__global__ void AddCUDA2D(const T* src, const T* target, T* out, const size_t dimX, const size_t dimY)
{
    const int tid = Grid2DTID(blockIdx.x, blockIdx.y, threadIdx.x, threadIdx.y, threadIdx.z);
    const int tDimY = GDim_Y * blockIdx.y + threadIdx.y;
    const int tDimX = GDim_X * blockIdx.x + threadIdx.x;
    if (tDimX >= dimX || tDimY >= dimY) return;
    out[tid] = src[tid] + target[tid];
}

template <typename T>
__global__ void AddCUDA3D(const T* src, const T* target, T* out, const size_t dimX, const size_t dimY,
                          const size_t dimZ)
{
    const int tid = Grid3DTID(blockIdx.x, blockIdx.y, blockIdx.z, threadIdx.x, threadIdx.y, threadIdx.z);
    const size_t tDimZ = GDim_Z * blockIdx.z + threadIdx.z;
    const size_t tDimY = GDim_Y * blockIdx.y + threadIdx.y;
    const size_t tDimX = GDim_X * blockIdx.x + threadIdx.x;

    if (tDimX >= dimX || tDimY >= dimY || tDimZ >= dimZ) return;
    out[tid] = src[tid] + target[tid];
}

template <typename T>
template <typename S>
void ushionn::Tensor<T>::Multiply(const S x)
{
    if (device_ == Device::CUDA)
    {
        if (dimSize_ == 1 && dataSize_ <= 1024)
        {
            MultiplyCUDA1D<T, S><<<dim3(1, 1, 1), dim3(dims_[0], 1, 1)> > >(data_.get(), x, data_.get(), dims_[0]);
        }
        else if (dimSize_ == 1 && dataSize_ > 1024)
        {
            MultiplyCUDA1D<T, S><<<dim3(ceil(dataSize_ / 1024.f), 1, 1), dim3(blockSize1D, 1, 1)> > >(
                data_.get(), x, data_.get(), dims_[0]);
        }
        else if (dimSize_ == 2 && dataSize_ <= 1024)
        {
            MultiplyCUDA2D<T, S>
                <<<dim3(1, 1, 1), dim3(dims_[1], dims_[0], 1)> > >(data_.get(), x, data_.get(), dims_[1], dims_[0]);
        }
        else if (dimSize_ == 2 && dataSize_ > 1024)
        {
            MultiplyCUDA2D<T, S>
                <<<dim3(ceil(dims_[1] / static_cast<float>(kblockSize2D)),
                        ceil(dims_[0] / static_cast<float>(kblockSize2D))),
                   dim3(blockSize2D, blockSize2D, 1)> > >(data_.get(), x, data_.get(), dims_[1], dims_[0]);
        }
        else if (dimSize_ == 3 && dataSize_ <= 1024)
        {
            MultiplyCUDA3D<T, S><<<dim3(1, 1, 1), dim3(dims_[2], dims_[1], dims_[0])> > >(data_.get(), x, data_.get(),
                                                                                          dims_[2], dims_[1], dims_[0]);
        }
        else if (dimSize_ == 3 && dataSize_ > 1024)
        {
            MultiplyCUDA3D<T, S><<<dim3(ceil(dims_[2] / static_cast<float>(kblockSize3DX)),
                                        ceil(dims_[1] / static_cast<float>(kblockSize3DYZ)),
                                        ceil(dims_[0] / static_cast<float>(kblockSize3DYZ))),
                                   dim3(blockSize3DX, blockSize3DYZ, blockSize3DYZ)> > >(data_.get(), x, data_.get(),
                                                                                         dims_[2], dims_[1], dims_[0]);
        }
        else
        {
            std::cerr << "Error : Tensor dim length must be less than 4" << std::endl;
            throw "Tensor dim length must be less than 4";
        }
    }
    else if (device_ == Device::CPU)
    {
        for (int i = 0; i < dataSize_; ++i) data_.get()[i] *= x;
    }
}

template <typename T>
void ushionn::Tensor<T>::Add(const Tensor& x)
{
    if (device_ == Device::CUDA && x.getDevice() == Device::CUDA && dims_ == x.dims_)
    {
        if (dimSize_ == 1 && dataSize_ <= 1024)
        {
            AddCUDA1D<T><<<dim3(1, 1, 1), dim3(dims_[0], 1, 1)> > >(data_.get(), x.data_.get(), data_.get(), dims_[0]);
        }
        else if (dimSize_ == 1 && dataSize_ > 1024)
        {
            AddCUDA1D<T><<<dim3(ceil(dataSize_ / 1024.f), 1, 1), dim3(blockSize1D, 1, 1)> > >(
                data_.get(), x.data_.get(), data_.get(), dims_[0]);
        }
        else if (dimSize_ == 2 && dataSize_ <= 1024)
        {
            AddCUDA2D<T><<<dim3(1, 1, 1), dim3(dims_[1], dims_[0], 1)> > >(data_.get(), x.data_.get(), data_.get(),
                                                                           dims_[1], dims_[0]);
        }
        else if (dimSize_ == 2 && dataSize_ > 1024)
        {
            AddCUDA2D<T><<<dim3(ceil(dims_[1] / static_cast<float>(kblockSize2D)),
                                ceil(dims_[0] / static_cast<float>(kblockSize2D))),
                           dim3(kblockSize2D, kblockSize2D, 1)> > >(data_.get(), x.data_.get(), data_.get(), dims_[1],
                                                                    dims_[0]);
        }
        else if (dimSize_ == 3 && dataSize_ <= 1024)
        {
            AddCUDA3D<T><<<dim3(1, 1, 1), dim3(dims_[2], dims_[1], dims_[0])> > >(
                data_.get(), x.data_.get(), data_.get(), dims_[2], dims_[1], dims_[0]);
        }
        else if (dimSize_ == 3 && dataSize_ > 1024)
        {
            AddCUDA3D<T><<<dim3(ceil(dims_[2] / static_cast<float>(kblockSize3DX)),
                                ceil(dims_[1] / static_cast<float>(kblockSize3DYZ)),
                                ceil(dims_[0] / static_cast<float>(kblockSize3DYZ))),
                           dim3(kblockSize3DX, kblockSize3DYZ, kblockSize3DYZ)> > >(
                data_.get(), x.data_.get(), data_.get(), dims_[2], dims_[1], dims_[0]);
        }
        else
        {
            std::cerr << "Error : Tensor dim must be 1, 2, 3" << std::endl;
            throw "Tensor dim must be 1, 2, 3";
        }
    }
    else if (device_ == Device::CPU && x.getDevice() == Device::CPU && dims_ == x.dims_)
    {
        for (int i = 0; i < dataSize_; ++i) data_.get()[i] += x.data_.get()[i];
    }
    else if (device_ == x.device_ && dims_ != x.dims_)
    {
        std::cerr << "Error : Tensors need to be in the same dimension" << std::endl;
        throw "Tensors need to be in the same dimension";
    }
    else
    {
        std::cerr << "Error : Tensors need to be in the same device" << std::endl;
        throw "Tensors need to be in the same device";
    }
}

template void ushionn::Tensor<int>::Multiply<int>(int);
template void ushionn::Tensor<int>::Multiply<float>(float);
template void ushionn::Tensor<float>::Multiply<int>(int);
template void ushionn::Tensor<float>::Multiply<float>(float);

#endif
