function saveh5(data, fname, varargin)
%
%    saveh5(data, outputfile)
%       or
%    saveh5(data, outputfile, options)
%    saveh5(data, outputfile, 'Param1',value1, 'Param2',value2,...)
%
%    Save a MATLAB struct (array) or cell (array) into an HDF5 file
%
%    author: Qianqian Fang (q.fang <at> neu.edu)
%
%    input:
%        data: a structure (array) or cell (array) to be stored.
%        fname: the output HDF5 (.h5) file name
%        options: (optional) Param/value pairs for user specified options
%            Root: the HDF5 path of the root object. If not given, the
%                actual variable name for the data input will be used as
%                the root object. The value shall not include '/'.
%    example:
%        a=struct('a',rand(5),'b','string','c',true,'d',2+3i,'e',{'test',[],1:5});
%        saveh5(a,'test.h5');
%
%    this file is part of EazyH5 Toolbox: https://github.com/fangq/eazyh5
%
%    License: GPLv3 or 3-clause BSD license, see https://github.com/fangq/eazyh5 for details
%


if(nargin<2)
    error('you must provide at least two inputs');
end

rootname=['/' inputname(1)];
opt=struct;

if(length(varargin)==1 && ischar(varargin{1}))
   rootname=[varargin{1} '/' inputname(1)];
else
   opt=varargin2struct(varargin{:});
end

if(isfield(opt,'root'))
   rootname=['/' opt.root];
end

try
    if(isa(fname,'H5ML.id'))
        fid=fname;
    else
        fid = H5F.create(fname, 'H5F_ACC_TRUNC', H5P.create('H5P_FILE_CREATE'), H5P.create('H5P_FILE_ACCESS'));
    end
    obj2h5(rootname,data,fid,1,opt);
catch ME
    if(exist('fid','var') && fid>0)
        H5F.close(fid);
    end
    rethrow(ME);
end

if(~isa(fname,'H5ML.id'))
    H5F.close(fid);
end

%%-------------------------------------------------------------------------
function oid=obj2h5(name, item,handle,level,varargin)

if(iscell(item))
    oid=cell2h5(name,item,handle,level,varargin{:});
elseif(isstruct(item))
    oid=struct2h5(name,item,handle,level,varargin{:});
elseif(ischar(item) || isa(item,'string'))
    oid=mat2h5(name,item,handle,level,varargin{:});
elseif(isa(item,'containers.Map'))
    oid=map2h5(name,item,handle,level,varargin{:});
elseif(isa(item,'categorical'))
    oid=cell2h5(name,cellstr(item),handle,level,varargin{:});
elseif(islogical(item) || isnumeric(item))
    oid=mat2h5(name,item,handle,level,varargin{:});
else
    oid=any2h5(name,item,handle,level,varargin{:});
end

%%-------------------------------------------------------------------------
function oid=idxobj2h5(name, idx, varargin)
oid=obj2h5(sprintf('%s%d',name,idx), varargin{:});

%%-------------------------------------------------------------------------
function oid=cell2h5(name, item,handle,level,varargin)

num=numel(item);
if(num>1)
    idx=reshape(1:num,size(item));
    idx=num2cell(idx);
    oid=cellfun(@(x,id) idxobj2h5(name, id, x, handle,level,varargin), item, idx, 'UniformOutput',false);
else
    oid=cellfun(@(x) obj2h5(name, x, handle,level,varargin), item, 'UniformOutput',false);
end

%%-------------------------------------------------------------------------
function oid=struct2h5(name, item,handle,level,varargin)

num=numel(item);
if(num>1)
    oid=obj2h5(name, num2cell(item),handle,level,varargin);
else
    pd = 'H5P_DEFAULT';
    gcpl = H5P.create('H5P_GROUP_CREATE');
    tracked = H5ML.get_constant_value('H5P_CRT_ORDER_TRACKED');
    indexed = H5ML.get_constant_value('H5P_CRT_ORDER_INDEXED');
    order = bitor(tracked,indexed);
    H5P.set_link_creation_order(gcpl,order);
    try
        handle=H5G.create(handle, name, pd,gcpl,pd);
        isnew=1;
    catch
        isnew=0;
    end

    names=fieldnames(item);
    oid=cell(1,length(names));
    for i=1:length(names)
        oid{i}=obj2h5(names{i},item.(names{i}),handle,level+1,varargin{:});
    end
    
    if(isnew)
        H5G.close(handle);
    end
end

%%-------------------------------------------------------------------------
function oid=map2h5(name, item,handle,level,varargin)

pd = 'H5P_DEFAULT';
gcpl = H5P.create('H5P_GROUP_CREATE');
tracked = H5ML.get_constant_value('H5P_CRT_ORDER_TRACKED');
indexed = H5ML.get_constant_value('H5P_CRT_ORDER_INDEXED');
order = bitor(tracked,indexed);
H5P.set_link_creation_order(gcpl,order);
try
    handle=H5G.create(handle, name, pd,gcpl,pd);
    isnew=1;
catch
    isnew=0;
end

names=item.keys;
oid=zeros(length(names));
for i=1:length(names)
    oid(i)=obj2h5(names{i},item(names{i}),handle,level+1,varargin{:});
end

if(isnew)
    H5G.close(handle);
end

%%-------------------------------------------------------------------------
function oid=mat2h5(name, item,handle,level,varargin)
if(isa(item,'string'))
    item=char(item);
end
typemap.char='H5T_C_S1';
typemap.string='H5T_C_S1';
typemap.double='H5T_IEEE_F64LE';
typemap.single='H5T_IEEE_F32LE';
typemap.logical='H5T_STD_U8LE';
typemap.uint8='H5T_STD_U8LE';
typemap.int8='H5T_STD_I8LE';
typemap.uint16='H5T_STD_U16LE';
typemap.int16='H5T_STD_I16LE';
typemap.uint32='H5T_STD_U32LE';
typemap.int32='H5T_STD_I32LE';
typemap.uint64='H5T_STD_U64LE';
typemap.int64='H5T_STD_I64LE';

pd = 'H5P_DEFAULT';
gcpl = H5P.create('H5P_GROUP_CREATE');
H5P.set_link_creation_order(gcpl,H5ML.get_constant_value('H5P_CRT_ORDER_TRACKED'));

if(isa(item,'logical'))
    item=uint8(item);
end

if(isreal(item))
    oid=H5D.create(handle,name,H5T.copy(typemap.(class(item))),H5S.create_simple(ndims(item), size(item),size(item)),pd);
    H5D.write(oid,'H5ML_DEFAULT','H5S_ALL','H5S_ALL',pd,item);
else
    typeid=H5T.copy(typemap.(class(item)));
    elemsize=H5T.get_size(typeid);
    memtype = H5T.create ('H5T_COMPOUND', elemsize*2);
    H5T.insert (memtype,'Real', 0, typeid);
    H5T.insert (memtype,'Imag', elemsize, typeid);
    oid=H5D.create(handle,name,memtype,H5S.create_simple(ndims(item), size(item),size(item)),pd);
    H5D.write(oid,'H5ML_DEFAULT','H5S_ALL','H5S_ALL',pd,struct('r',real(item),'i',imag(item)));
end
H5D.close(oid);

%%-------------------------------------------------------------------------
function oid=any2h5(name, item,handle,level,varargin)
pd = 'H5P_DEFAULT';

rawdata=getByteStreamFromArray(item);  % use undocumented matlab function
oid=H5D.create(handle,name,H5T.copy('H5T_STD_U8LE'),H5S.create_simple(ndims(rawdata), size(rawdata),size(rawdata)),pd);
H5D.write(oid,'H5ML_DEFAULT','H5S_ALL','H5S_ALL',pd,rawdata);

adata=class(item);
space_id=H5S.create_simple(ndims(adata), size(adata),size(adata));
attr_type = H5A.create(oid,'MATLABObjectClass',H5T.copy('H5T_C_S1'),space_id,H5P.create('H5P_ATTRIBUTE_CREATE'));
H5A.write(attr_type,'H5ML_DEFAULT',adata);
H5A.close(attr_type);

adata=size(item);
space_id=H5S.create_simple(ndims(adata), size(adata),size(adata));
attr_size = H5A.create(oid,'MATLABObjectSize',H5T.copy('H5T_NATIVE_DOUBLE'),space_id,H5P.create('H5P_ATTRIBUTE_CREATE'));
H5A.write(attr_size,'H5ML_DEFAULT',adata);
H5A.close(attr_size);

H5D.close(oid);
