function data=regrouph5(root, varargin)
%
%    data=regrouph5(root)
%       or
%    data=regrouph5(root,type)
%    data=regrouph5(root,{'nameA','nameB',...})
%
%    Processing an HDF5 based data and group indexed datasets into a
%    cell array
%
%    author: Qianqian Fang (q.fang <at> neu.edu)
%
%    input:
%        root: the raw input HDF5 data structure (loaded from loadh5.m)
%        type: if type is set as a cell array of strings, it restrict the
%              grouping only to the subset of field names in this list;
%              if type is a string as 'snirf', it is the same as setting 
%              type as {'aux','data','nirs','stim','measurementList'}.
%
%    output:
%        data: a reorganized matlab structure.
%
%    example:
%        a=struct('a1',rand(5),'a2','string','a3',true,'d',2+3i,'e',{'test',[],1:5});
%        regrouph5(a)
%        saveh5(a,'test.h5');
%        rawdata=loadh5('test.h5')
%        data=regrouph5(rawdata)
%
%    this file is part of EazyH5 Toolbox: https://github.com/fangq/eazyh5
%
%    License: GPLv3 or 3-clause BSD license, see https://github.com/fangq/eazyh5 for details
%

if(nargin<1)
    help regrouph5;
    return;
end

dict={};
if(~isempty(varargin))
    if(ischar(varargin{1}) && strcmpi(varargin{1},'snirf'))
        dict={'aux','data','nirs','stim','measurementList'};
    elseif(iscell(varargin{1}))
        dict=varargin{1};
    end
end

data=struct;
if(isstruct(root))
    data=repmat(struct,size(root));
    names=fieldnames(root);
    newnames=struct();

    for i=1:length(names)
        item=regexp(names{i},'^(\D+)(\d+)$','tokens');
        if(~isempty(item) && str2double(item{1}{2})~=0)
            if(~isfield(newnames,item{1}{1}))
                newnames.(item{1}{1})=str2double(item{1}{2});
            else
                newnames.(item{1}{1})=[newnames.(item{1}{1}), str2double(item{1}{2})];
            end
        else
            for j=1:length(root)
                if(isstruct(root(j).(names{i})))
                    data(j).(names{i})=regrouph5(root(j).(names{i}));
                else
                    data(j).(names{i})=root(j).(names{i});
                end
            end
        end
    end

    names=fieldnames(newnames);
    if(~isempty(dict))
        names=intersect(names,dict);
    end

    for i=1:length(names)
        len=length(newnames.(names{i}));
        idx=newnames.(names{i});
        if(len==1 || min(idx)~=1 || max(idx)~=len)
            for j=1:len
                dataname=sprintf('%s%d',names{i},idx(j));
                for k=1:length(root)
                    if(isstruct(root(k).(dataname)))
                        data(k).(dataname)=regrouph5(root(k).(dataname));
                    else
                        data(k).(dataname)=root(k).(dataname);
                    end
                end
            end
            continue;
        end
        for j=1:length(data)
            data(j).(names{i})=cell(1,len);
        end
        idx=sort(idx);
        for j=1:len
            for k=1:length(root)
                obj=root(k).(sprintf('%s%d',names{i},idx(j)));
                if(isstruct(obj))
                    data(k).(names{i}){j}=regrouph5(obj);
                else
                    data(k).(names{i}){j}=obj;
                end
            end
        end
        try
            data.(names{i})=cell2mat(data.(names{i}));
        catch
        end
    end
end
