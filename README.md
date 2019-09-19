# EazyH5 Toolbox - An easy-to-use HDF5 data interface (loadh5 and saveh5)

* Copyright (C) 2019  Qianqian Fang <q.fang at neu.edu>
* License: GNU General Public License version 3 (GPL v3) or Apache License 2.0, see License*.txt
* Version: 0.4
* URL: http://github.com/fangq/eazyh5

## Overview

EazyH5 is a streamlined, fast, compact and portable MATLAB object to HDF5
export/import interface. It contains two easy-to-use functions - `loadh5.m` and
saveh5.m. The `saveh5.m` can handle most MATLAB data types, including struct,
struct arrays, cells, cell arrays, real and complex arrays, strings, 
and `containers.Map` objects. All other data classes (such as a table, digraph, 
etc) can also be stored/loaded seemlessly using an internal data serialization 
interface (MATLAB only).

EazyH5 stores complex numerical arrays using the composite data types in an
HDF5 dataset. The real-part of the data are stored as `Real` and the imaginary
parts are stored as the `Imag` component. The loadh5.m automatically convert
such data structure to a complex array.

Because HDF5 does not directly support 1D/N-D cell arrays or struct arrays,
EazyH5 converts these data structures into data groups with names of the 
following format
```
    ['/hdf5/path/.../fieldname',num2str(idx1d)]
```
where `fieldname` is the variable/field name to the cell/struct array object, 
and `idx1d` is the 1-D integer index of the cell/struct array. We also provide
a function, `regrouph5.m` to automatically collapse these group/dataset names
into cell/struct arrays after loading the data using `loadh5.m`. See examples
below.

## Installation

The EazyH5 toolbox can be installed using a single command
```
    addpath('/path/to/eazyh5');
```
where the `/path/to/eazyh5` should be replaced by the unzipped folder
of the toolbox (i.e. the folder containing `loadh5.m/saveh5.m`).

## Usage

### `saveh5` - Save a MATLAB struct (array) or cell (array) into an HDF5 file
Example:
```
  a=struct('a',rand(5),'b','string','c',true,'d',2+3i,'e',{'test',[],1:5});
  saveh5(a,'test.h5');
  saveh5(a,'test2.h5','Root','rootname');
```
### `loadh5` - Load data in an HDF5 file to a MATLAB structure.
Example:
```
  data=loadh5('test.h5');
```
### `regrouph5` - Processing an HDF5 based data and group indexed datasets into a cell array
Example:
```
  a=struct('a1',rand(5),'a2','string','a3',true,'d',2+3i,'e',{'test',[],1:5});
  a(1).a1=0; a(2).a2='test';
  data=regrouph5(a)
  saveh5(a,'test.h5');
  rawdata=loadh5('test.h5')
  data=regrouph5(rawdata)
```

