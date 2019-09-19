function varargout=loadh5(filename, path)
%
% [data, meta] = loadh5(filename)
% [data, meta] = loadh5(root_id)
% [data, meta] = loadh5(filename, path_in_file)
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
%     path_in_file : optional
%         Path to the part of the HDF5 file to load
% output
%     data: a structure (array) or cell (array)
%
% This file is part of EazyH5 Toolbox: https://github.com/fangq/eazyh5
%
% This script is in the Public Domain. No warranty.
%

if nargin > 1
  path_parts = regexp(path, '/', 'split');
else
  path = '';
  path_parts = [];
end

if(isa(filename,'H5ML.id'))
    loc=filename;
else
    loc = H5F.open(filename, 'H5F_ACC_RDONLY', 'H5P_DEFAULT');
end

try
  [varargout{1:nargout}]=load_one(loc, path_parts, path);
  H5F.close(loc);
catch exc
  H5F.close(loc);
  rethrow(exc);
end


function [data, meta]=load_one(loc, path_parts, full_path)
% Load a record recursively.

while ~isempty(path_parts) && strcmp(path_parts{1}, '')
  path_parts = path_parts(2:end);
end

data = struct();
meta = struct();

num_objs = H5G.get_num_objs(loc);

% 
% Load groups and datasets
%
for j_item=0:num_objs-1
  objtype = H5G.get_objtype_by_idx(loc, j_item);
  objname = H5G.get_objname_by_idx(loc, j_item);
  
  attr=struct();

  % objtype index 
  objtype = objtype+1;
  
  if objtype == 1
    % Group
    name = regexprep(objname, '.*/', '');
  
    if isempty(path_parts) || strcmp(path_parts{1}, name)
      if ~isempty(regexp(name,'.+','once'))
	group_loc = H5G.open(loc, name);
	try
	  [sub_data, sub_meta] = load_one(group_loc, path_parts(2:end), full_path);
	  H5G.close(group_loc);
	catch exc
	  H5G.close(group_loc);
	  rethrow(exc);
        end
        name=genvarname(name);
	if isempty(path_parts)
          data.(name) = sub_data;
          meta.(name) = sub_meta;
	else
	  data = sub_data;
          meta = sub_meta;
	  return
	end
      end
    end
   
  elseif objtype == 2
    % Dataset
    name = regexprep(objname, '.*/', '');
  
    if isempty(path_parts) || strcmp(path_parts{1}, name)
      if ~isempty(regexp(name,'.+','once'))
	dataset_loc = H5D.open(loc, name);
	try
	  sub_data = H5D.read(dataset_loc, ...
	      'H5ML_DEFAULT', 'H5S_ALL','H5S_ALL','H5P_DEFAULT');
          [status, count, attr]=H5A.iterate(dataset_loc, 'H5_INDEX_NAME', 'H5_ITER_NATIVE', 0, @getattribute, attr);
	  H5D.close(dataset_loc);
	catch exc
	  H5D.close(dataset_loc);
	  rethrow(exc);
	end
	
	sub_data = fix_data(sub_data, attr);
	name=genvarname(name);
	if isempty(path_parts)
          data.(name) = sub_data;
          meta.(name) = attr;
	else
	  data = sub_data;
          meta = attr;
	  return
	end
      end
    end
  end
end

% Check that we managed to load something if path walking is in progress
if ~isempty(path_parts)
  error('Path "%s" not found in the HDF5 file', full_path);
end


%--------------------------------------------------------------------------
function data=fix_data(data, attr)
% Fix some common types of data to more friendly form.

if isstruct(data)
  fields = fieldnames(data);
  if(length(intersect(fields,{'Real','Imag'}))==2)
    if isnumeric(data.Real) && isnumeric(data.Imag)
      data = data.Real + 1j*data.Imag;
    end
  end

  if(length(intersect(fields,{'r','i'}))==2)
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

if isnumeric(data) && ndims(data) > 1
  % permute dimensions
  data = permute(data, fliplr(1:ndims(data)));
end

%--------------------------------------------------------------------------
function [status, dataout]= getattribute(loc_id,attr_name,info,datain)
status=0;
attr_id = H5A.open(loc_id, attr_name, 'H5P_DEFAULT');
datain.(attr_name) = H5A.read(attr_id, 'H5ML_DEFAULT');
H5A.close(attr_id);
dataout=datain;
