function varargout=loadh5(filename, path, varargin)
%
% [data, meta] = loadh5(filename)
% [data, meta] = loadh5(root_id)
% [data, meta] = loadh5(filename, rootpath)
% [data, meta] = loadh5(filename, rootpath,'param1',value1,'param2',value2,...)
%
% Load data in an HDF5 file to a MATLAB structure.
%
% Author: Pauli Virtanen <pav at iki.fi>
%
% Updated by Qianqian Fang <q.fang at neu.edu>
%   - reading attributes and return as 2nd output 'meta'
%   - handle arbitrary matlab object saved by saveh5.m
%   - support Real/Imag composite record for complex arrays
%
% input
%     filename
%         Name of the file to load data from
%     root_id: an HDF5 handle (of type 'H5ML.id' in MATLAB)
%     rootpath : optional
%         Root path to read part of the HDF5 file to load
%     param/value: acceptable optional parameters include
%       'order': 'creation' - creation order, or 'alphabet' - alphabetic
%
% output
%     data: a structure (array) or cell (array)
%     meta: optional output to store the attributes stored in the file
%
% This file is part of EazyH5 Toolbox: https://github.com/fangq/eazyh5
%
% License: GPLv3 or 3-clause BSD license, see https://github.com/fangq/eazyh5 for details
%

opt=varargin2struct(varargin{:});

if nargin <= 1
  path = '';
end

if(isa(filename,'H5ML.id'))
    loc=filename;
else
    loc = H5F.open(filename, 'H5F_ACC_RDONLY', 'H5P_DEFAULT');
end

opt.rootpath=path;
   
try
  if(nargin>1 && ~isempty(path))
      try
          rootgid=H5G.open(loc,path);
          [varargout{1:nargout}]=load_one(rootgid, opt);
          H5G.close(rootgid);
      catch
          [gname,dname]=fileparts(path);
          rootgid=H5G.open(loc,gname);
          [status, res]=group_iterate(rootgid,dname,struct('data',struct,'meta',struct,'opt',opt));
          if(nargout>0)
              varargout{1}=res.data;
          elseif(nargout>1)
              varargout{2}=res.meta;
          end
          H5G.close(rootgid);
      end
  else
      [varargout{1:nargout}]=load_one(loc, opt);
  end
  H5F.close(loc);
catch ME
  H5F.close(loc);
  rethrow(ME);
end

%--------------------------------------------------------------------------
function [data, meta]=load_one(loc, opt)

data = struct();
meta = struct();
inputdata=struct('data',data,'meta',meta,'opt',opt);
order='H5_INDEX_CRT_ORDER';
if(isfield(opt,'order') && strcmpi(opt.order,'alphabet'))
   order='H5_INDEX_NAME';
end

% Load groups and datasets
try
    [status,count,inputdata] = H5L.iterate(loc,order,'H5_ITER_INC',0,@group_iterate,inputdata);
catch
    if(strcmp(order,'H5_INDEX_CRT_ORDER'))
        [status,count,inputdata] = H5L.iterate(loc,'H5_INDEX_NAME','H5_ITER_INC',0,@group_iterate,inputdata);
    end
end

data=inputdata.data;
meta=inputdata.meta;

%--------------------------------------------------------------------------
function [status, res]=group_iterate(group_id,objname,inputdata)
status=0;
attr=struct();

try
  data=inputdata.data;
  meta=inputdata.meta;

  % objtype index 
  info = H5G.get_objinfo(group_id,objname,0);
  objtype = info.type;
  objtype = objtype+1;
  
  if objtype == 1
    % Group
    name = regexprep(objname, '.*/', '');
  
	group_loc = H5G.open(group_id, name);
	try
	  [sub_data, sub_meta] = load_one(group_loc, inputdata.opt);
	  H5G.close(group_loc);
	catch ME
	  H5G.close(group_loc);
	  rethrow(ME);
	end
	name=genvarname(name);
    data.(name) = sub_data;
    meta.(name) = sub_meta;
    
  elseif objtype == 2
    % Dataset
    name = regexprep(objname, '.*/', '');
  
	dataset_loc = H5D.open(group_id, name);
	try
	  sub_data = H5D.read(dataset_loc, ...
	      'H5ML_DEFAULT', 'H5S_ALL','H5S_ALL','H5P_DEFAULT');
          [status, count, attr]=H5A.iterate(dataset_loc, 'H5_INDEX_NAME', 'H5_ITER_INC', 0, @getattribute, attr);
	  H5D.close(dataset_loc);
	catch exc
	  H5D.close(dataset_loc);
	  rethrow(exc);
	end
	
	sub_data = fix_data(sub_data, attr);
	name=genvarname(name);
    data.(name) = sub_data;
    meta.(name) = attr;
  end
catch ME
    rethrow(ME);
end
res=struct('data',data,'meta',meta,'opt',inputdata.opt);

%--------------------------------------------------------------------------
function data=fix_data(data, attr)
% Fix some common types of data to more friendly form.

if isstruct(data)
  fields = fieldnames(data);

  if(length(intersect(fields,{'SparseIndex','Real'}))==2)
    if isnumeric(data.SparseIndex) && isnumeric(data.Real)
      if(nargin>1 && isstruct(attr))
          if(isfield(attr,'SparseArraySize'))
              spd=sparse(1,prod(attr.SparseArraySize));
              if(isfield(data,'Imag'))
                  spd(data.SparseIndex)=complex(data.Real,data.Imag);
              else
                  spd(data.SparseIndex)=data.Real;
              end
              data=reshape(spd,attr.SparseArraySize(:)');
          end
      end
    end
  end

  if(isstruct(data) && length(intersect(fieldnames(data),{'Real','Imag'}))==2)
    if isnumeric(data.Real) && isnumeric(data.Imag)
      data = data.Real + 1j*data.Imag;
    end
  end

  if(isstruct(data) && length(intersect(fieldnames(data),{'r','i'}))==2)
    if isnumeric(data.r) && isnumeric(data.i)
      data = data.r + 1j*data.i;
    end
  end
end

if(isa(data,'uint8') || isa(data,'int8'))
  if(nargin>1 && isstruct(attr))
      if(isfield(attr,'MATLABObjectClass'))
         data=getArrayFromByteStream(data); % use undocumented function
      end
  end
end

% if isnumeric(data) && ndims(data) > 1
%   % permute dimensions
%   data = permute(data, fliplr(1:ndims(data)));
% end

%--------------------------------------------------------------------------
function [status, dataout]= getattribute(loc_id,attr_name,info,datain)
status=0;
attr_id = H5A.open(loc_id, attr_name, 'H5P_DEFAULT');
datain.(attr_name) = H5A.read(attr_id, 'H5ML_DEFAULT');
H5A.close(attr_id);
dataout=datain;
