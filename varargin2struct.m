function opt = varargin2struct(varargin)
%
% opt=varargin2struct('param1',value1,'param2',value2,...)
%   or
% opt=varargin2struct(...,optstruct,...)
%
% convert a series of input parameters into a structure
%
% authors:Qianqian Fang (q.fang <at> neu.edu)
% date: 2012/12/22
%
% input:
%      'param', value: the input parameters should be pairs of a string and a value
%       optstruct: if a parameter is a struct, the fields will be merged to the output struct
%
% output:
%      opt: a struct where opt.param1=value1, opt.param2=value2 ...
%
% license:
%     BSD or GPL version 3, see LICENSE_{BSD,GPLv3}.txt files for details
%
% -- this function is part of JSONLab toolbox (https://iso2mesh.sf.net/cgi-bin/index.cgi?jsonlab)
%

len = length(varargin);
opt = struct;
if (len == 0)
    return
end
i = 1;
while (i <= len)
    if (isstruct(varargin{i}))
        opt = mergestruct(opt, varargin{i});
    elseif ((ischar(varargin{i}) || isa(varargin{i}, 'string')) && i < len)
        opt.(lower(varargin{i})) = varargin{i + 1};
        i = i + 1;
    else
        error('input must be in the form of ...,''name'',value,... pairs or structs');
    end
    i = i + 1;
end
