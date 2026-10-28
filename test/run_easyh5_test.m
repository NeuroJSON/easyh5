function run_easyh5_test(tests)
%
% run_easyh5_test
%   or
% run_easyh5_test(tests)
% run_easyh5_test({'basic', 'types', 'struct', 'shape', 'opt', 'maxbytes', 'storage', 'handle'})
%
% Unit testing for EasyH5
%
% authors:Qianqian Fang (q.fang <at> neu.edu)
%
% input:
%      tests: a cell array of strings, possible elements include
%         'basic':  numeric arrays of various shapes
%         'types':  integer, logical, char, complex and sparse data
%         'struct': structs, nested structs, cells and struct arrays
%         'shape':  the rank and dimensions of the datasets written to the file
%         'opt':    saveh5/loadh5 options (rootname, compression, append)
%         'maxbytes': loadh5 MaxBytes option, returning headers for large data
%         'storage': the storage records returned as the third output of loadh5
%         'handle': passing an already open HDF5 file id instead of a name
%         'known':  reproduce known open defects; not run by default
%
% All tests write to a uniquely named temporary file obtained from tempname
% and remove it afterwards. HDF5 has no portable in-memory file support - the
% core virtual file driver needs H5P.set_fapl_core, which the oct-hdf5 package
% does not provide - and a file also lets the tests inspect the dataset layout
% with the low-level API rather than trusting a loadh5/saveh5 round trip to
% agree with itself.
%
% license:
%     GPLv3 or 3-clause BSD license, see https://github.com/NeuroJSON/easyh5
%
% -- this function is part of EasyH5 toolbox (https://github.com/NeuroJSON/easyh5)
%

if (nargin == 0)
    tests = {'basic', 'types', 'struct', 'shape', 'opt', 'maxbytes', 'storage', 'handle'};
end

% remove every temporary file, including when a test throws part way through
cleaner = onCleanup(@() h5temp('cleanup'));

test_easyh5('reset');

if (~hashdf5backend)
    fprintf(['the low-level HDF5 interface is not available, skipping.\n' ...
             'In GNU Octave it is provided by the oct-hdf5 package:\n\t' ...
             'pkg install https://github.com/NeuroJSON/oct-hdf5/archive/refs/tags/git20260830.zip\n']);
    return
end

%%
if (ismember('basic', tests))
    banner('Test numeric array round trips');

    checkroundtrip('scalar', 42);
    checkroundtrip('negative scalar', -7.25);
    checkroundtrip('row vector', 1:10);
    checkroundtrip('column vector', (1:10)');
    checkroundtrip('2d matrix', magic(4));
    checkroundtrip('3d array', reshape(1:24, [2 3 4]));
    checkroundtrip('4d array', reshape(1:16, [2 2 2 2]));
    checkroundtrip('single precision', single([1.5 2.5 3.5]));
    checkroundtrip('large values', [1e300 -1e300]);
    checkroundtrip('special floats', [NaN Inf -Inf 0]);
    checkroundtrip('empty array', []);
end

%%
if (ismember('types', tests))
    banner('Test data types');

    checkroundtrip('int8', int8([-128 0 127]));
    checkroundtrip('uint8', uint8([0 128 255]));
    checkroundtrip('int16', int16([-32768 32767]));
    checkroundtrip('int32', int32([-2147483648 2147483647]));
    checkroundtrip('int64', int64([-9007199254740993 9007199254740993]));
    checkroundtrip('uint64', uint64([0 18446744073709551615]));
    checkroundtrip('logical scalar', true);
    checkroundtrip('logical array', logical([1 0 1; 0 1 0]));

    % complex and sparse arrays are stored as a compound type, so they take a
    % different path through the Transpose handling than a dense real array.
    % The asymmetric cases below are the ones that matter: a symmetric input
    % such as sparse(eye(n)) equals its own transpose and would pass either way
    checkroundtrip('complex vector', [1 + 2i, 3 - 4i, -5 + 6i]);
    checkroundtrip('complex matrix', complex(magic(3), magic(3)'));
    checkroundtrip('complex column', [1 + 1i; 2 - 2i]);
    checkroundtrip('sparse symmetric', sparse(eye(5)));
    checkroundtrip('sparse asymmetric', sparse([1 0 0; 0 0 2; 0 3 0]));
    checkroundtrip('sparse non square', sparse([1 0 0 4; 0 0 2 0]));
    checkroundtrip('sparse complex', sparse([1 + 2i 0; 0 3 - 4i]));

    % the transpose must be an identity round trip regardless of the setting
    checkroundtrip('complex no transpose', [1 + 2i, 3 - 4i], 'Transpose', 0);
    checkroundtrip('sparse no transpose', sparse([1 0 0; 0 0 2; 0 3 0]), 'Transpose', 0);
end

%%
if (ismember('struct', tests))
    banner('Test structured data');

    checkroundtrip('flat struct', struct('a', 1, 'b', 2.5));
    checkroundtrip('numeric struct', struct('num', 1:5, 'flag', true));
    checkroundtrip('nested struct', struct('x', struct('y', struct('z', magic(3)))));
    checkroundtrip('struct with cell', struct('c', {{1, 'a'}}), 'Regroup', 1);
    checkroundtrip('struct with empty', struct('e', [], 'f', 1));

    % a cell at the top level is stored as one indexed object per element, and
    % loadh5 only rebuilds them into a single value when Regroup is requested;
    % a cell of scalars comes back as a plain array
    fname = h5temp();
    saveh5({1, 2, 3}, fname, 'rootname', 'v');
    plain = loadh5(fname);
    test_easyh5('cell becomes indexed objects', sort(fieldnames(plain))', {'v1', 'v2', 'v3'});
    grouped = loadh5(fname, 'Regroup', 1);
    test_easyh5('Regroup rebuilds the cell', grouped.v, [1 2 3]);

    % a field name that is not a valid identifier must survive the hex encoding
    s = struct();
    s.(encodevarname('has space')) = 7;
    fname = h5temp();
    saveh5(s, fname, 'rootname', 'r');
    back = loadh5(fname);
    test_easyh5('encoded field name', back.r.(encodevarname('has space')), 7);
end

%%
if (ismember('shape', tests))
    banner('Test dataset rank and dimensions in the file');

    % a plain vector is a 2-D MATLAB array, and is stored as a rank-2 dataset;
    % this is what makes savesnirf wrap 1-D fields in a marker object before
    % calling saveh5, so pin the current behaviour
    fname = h5temp();
    saveh5([700 800 900], fname, 'rootname', 'wl');
    [rank, dims] = datasetshape(fname, '/wl');
    test_easyh5('row vector rank', rank, 2);
    test_easyh5('row vector dims', sort(dims(:)'), [1 3]);

    fname = h5temp();
    saveh5(magic(4), fname, 'rootname', 'm');
    [rank, dims] = datasetshape(fname, '/m');
    test_easyh5('2d matrix rank', rank, 2);
    test_easyh5('2d matrix dims', sort(dims(:)'), [4 4]);

    fname = h5temp();
    saveh5(reshape(1:24, [2 3 4]), fname, 'rootname', 'v');
    [rank, dims] = datasetshape(fname, '/v');
    test_easyh5('3d array rank', rank, 3);
    test_easyh5('3d array dims', sort(dims(:)'), [2 3 4]);

    fname = h5temp();
    saveh5(7, fname, 'rootname', 's');
    [rank, dims] = datasetshape(fname, '/s');
    test_easyh5('scalar rank', rank, 0);
end

%%
if (ismember('opt', tests))
    banner('Test saveh5/loadh5 options');

    % rootname controls the name of the top level object
    fname = h5temp();
    saveh5(magic(3), fname, 'rootname', 'custom');
    back = loadh5(fname);
    test_easyh5('rootname is honored', isfield(back, 'custom'), true);
    test_easyh5('rootname payload', back.custom, magic(3));

    % loading one path only returns just that subtree
    fname = h5temp();
    saveh5(struct('one', 1, 'two', [4 5 6]), fname, 'rootname', 'r');
    part = loadh5(fname, '/r/two');
    test_easyh5('load a single path', part.two, [4 5 6]);
    whole = loadh5(fname, '/r');
    test_easyh5('load a group path', sort(fieldnames(whole))', {'one', 'two'});
    test_easyh5('options as a struct', loadh5(fname, struct('Transpose', 1)), loadh5(fname, 'Transpose', 1));

    % append must keep the objects written by the earlier call
    fname = h5temp();
    saveh5(struct('first', 11), fname, 'rootname', 'a');
    saveh5(struct('second', 22), fname, 'rootname', 'b', 'append', 1);
    back = loadh5(fname);
    test_easyh5('append keeps old root', back.a.first, 11);
    test_easyh5('append adds new root', back.b.second, 22);

    % Compression uses the native HDF5 deflate filter, which needs
    % H5P.set_chunk and H5P.set_deflate; oct-hdf5 does not wrap either, so skip
    % these when the backend can not compress
    if (candeflate)
        fname = h5temp();
        big = repmat(1:50, 20, 1);
        saveh5(big, fname, 'rootname', 'z', 'Compression', 'deflate');
        back = loadh5(fname);
        test_easyh5('deflate round trip', back.z, big);

        plain = h5temp();
        saveh5(big, plain, 'rootname', 'z');
        zipped = dir(fname);
        unzipped = dir(plain);
        test_easyh5('deflate shrinks the file', zipped.bytes < unzipped.bytes, true);

        % an unknown filter name must be rejected rather than silently ignored
        failed = false;
        try
            saveh5(big, h5temp(), 'rootname', 'z', 'Compression', 'nosuchfilter');
        catch
            failed = true;
        end
        test_easyh5('unknown filter is rejected', failed, true);
    end
end

%%
if (ismember('maxbytes', tests))
    banner('Test the MaxBytes option of loadh5');

    % header fields are named by encodevarname, which differs between MATLAB
    % (x0x5F_ArrayType_) and GNU Octave (_ArrayType_)
    ftype = encodevarname('_ArrayType_');
    fsize = encodevarname('_ArraySize_');
    fcomplex = encodevarname('_ArrayIsComplex_');
    frank = encodevarname('_H5Rank_');
    flink = encodevarname('_DataLink_');

    % a header must report the class and size that a full load would return,
    % with either Transpose setting
    cansign = hasmethod('H5T', 'get_sign');
    vals = {'scalar', 42; 'row', 1:10; 'column', (1:10)'; 'matrix', magic(4) + 0.5; ...
            '3d', reshape(1:24, [2 3 4]); 'int32', int32(magic(3)); 'uint8', uint8([1 2; 3 4; 5 6]); ...
            'single', single(rand(3, 5)); 'complex', complex(magic(3), magic(3)'); ...
            'complex column', [1 + 1i; 2 - 2i]};
    for i = 1:size(vals, 1)
        for tp = [1 0]
            fname = h5temp();
            saveh5(vals{i, 2}, fname, 'rootname', 'v', 'Transpose', tp);
            full = loadh5(fname, 'Transpose', tp);
            hdr = loadh5(fname, 'Transpose', tp, 'MaxBytes', 0);
            tag = sprintf('%s header (transpose %d)', vals{i, 1}, tp);
            if (~isstruct(hdr.v) && ~cansign && (isinteger(full.v) || ~isreal(full.v)))
                % without H5T.get_sign or the compound member functions (as in
                % oct-hdf5), integer and complex datasets are read in full
                test_easyh5([tag ' read in full'], hdr.v, full.v);
                continue
            end
            test_easyh5([tag ' type'], hdr.v.(ftype), class(full.v));
            test_easyh5([tag ' size'], hdr.v.(fsize), size(full.v));
            test_easyh5([tag ' complex flag'], isfield(hdr.v, fcomplex), ~isreal(full.v));
        end
    end

    % only datasets larger than MaxBytes are replaced; strings are always read
    fname = h5temp();
    saveh5(struct('small', 1:3, 'big', rand(20, 30), 'name', 'label'), fname, 'rootname', 'r');
    full = loadh5(fname);
    part = loadh5(fname, 'MaxBytes', 1000);
    test_easyh5('small dataset is read', part.r.small, full.r.small);
    test_easyh5('large dataset becomes a header', isstruct(part.r.big), true);
    test_easyh5('header size', part.r.big.(fsize), [20 30]);
    test_easyh5('header rank', part.r.big.(frank), 2);
    test_easyh5('header data link', regexp(part.r.big.(flink), ':\$\.r\.big$', 'once') > 0, true);
    test_easyh5('string is read', part.r.name, full.r.name);
    test_easyh5('threshold is inclusive', isnumeric(getfield(loadh5(fname, 'MaxBytes', 4800), 'r', 'big')), true);
    test_easyh5('default reads everything', loadh5(fname, 'MaxBytes', inf), full);
    if (exist('jdatadecode', 'file') && exist('jdlink', 'file'))
        test_easyh5('data link resolves to the dataset', jdatadecode(part.r.big, 'MaxLinkLevel', 1), full.r.big);
    end

    [rank, dims] = datasetshape(fname, '/r/small');
    hdr = loadh5(fname, 'MaxBytes', 0);
    test_easyh5('1-d rank in header', hdr.r.small.(frank), rank);
end

%%
if (ismember('storage', tests))
    banner('Test the storage output of loadh5');

    fname = h5temp();
    saveh5(struct('s', 7, 'v', 1:4, 'm', magic(3), 'i', int16([1 2]), 'u', uint8(5), 'txt', 'label', ...
                  'g', struct('x', 1)), fname, 'rootname', 'r');
    [data, meta, st] = loadh5(fname);
    test_easyh5('storage keeps the data', data, loadh5(fname));
    rec = @(p) st(strcmp({st.path}, p));
    test_easyh5('storage group record', [rec('/r').isgroup, rec('/r').nlinks], [true 7]);
    test_easyh5('storage nested group', rec('/r/g').nlinks, 1);
    test_easyh5('storage scalar rank', rec('/r/s').rank, 0);
    [rank, dims] = datasetshape(fname, '/r/v');
    test_easyh5('storage vector rank and dims', {rec('/r/v').rank, rec('/r/v').dims}, {rank, double(dims(:)')});
    test_easyh5('storage matrix rank', rec('/r/m').rank, 2);
    test_easyh5('storage float class', {rec('/r/m').class, rec('/r/m').bytes}, {'float', 8});
    test_easyh5('storage int16', {rec('/r/i').class, rec('/r/i').bytes, rec('/r/i').signed}, {'integer', 2, true});
    test_easyh5('storage uint8', {rec('/r/u').class, rec('/r/u').signed}, {'integer', false});
    test_easyh5('storage string', rec('/r/txt').class, 'string');
    [rank, dims] = datasetshape(fname, '/r/m');
    test_easyh5('storage dims match the file', rec('/r/m').dims, double(dims(:)'));
    [~, ~, sub] = loadh5(fname, '/r/g');
    test_easyh5('storage of a subpath', {sub.path}, {'/r/g', '/r/g/x'});
    [~, ~, big] = loadh5(fname, 'MaxBytes', 0);
    test_easyh5('storage with headers', {big(strcmp({big.path}, '/r/m')).class, big(strcmp({big.path}, '/r/m')).rank}, {'float', 2});
end

%%
if (ismember('handle', tests) && canusefileid)
    banner('Test passing an open file id');

    % saveh5 and loadh5 both accept an H5ML.id, which is how callers write into
    % a file they opened themselves.
    %
    % note the two differ in who owns the handle: saveh5 leaves a caller
    % supplied id open (saveh5.m, "if (~isa(fname, 'H5ML.id'))"), while loadh5
    % closes it unconditionally, so neither id is closed here
    fname = h5temp();
    fid = H5F.create(fname, 'H5F_ACC_TRUNC', 'H5P_DEFAULT', 'H5P_DEFAULT');
    saveh5(struct('inside', 5), fid, 'rootname', 'h');
    clear fid;
    back = loadh5(fname);
    test_easyh5('save via file id', back.h.inside, 5);

    fid = H5F.open(fname, 'H5F_ACC_RDONLY', 'H5P_DEFAULT');
    back2 = loadh5(fid);
    clear fid;
    test_easyh5('load via file id', back2.h.inside, 5);
end

%%
if (ismember('known', tests))
    banner('Reproduce known open defects (not part of the default run)');

    % saveh5 transposes a char array before writing it, and loadh5 only undoes
    % the transpose for numeric data, so in GNU Octave a 1xN string comes back
    % as Nx1. In MATLAB the same string is written as a variable length string
    % with a scalar dataspace, so the shape survives and this passes
    checkroundtrip('char keeps orientation', 'hello easyh5');
    checkroundtrip('struct with char field', struct('num', 1:5, 'txt', 'label'));
end

%%
[total, failed, faillist] = test_easyh5('summary');

banner(sprintf('Totals: %d passed, %d failed, %d total', total - failed, failed, total));

if (total == 0)
    error('no unit test was executed, please check the requested test categories');
end

if (failed > 0)
    failnames = sprintf('\n\t%s', faillist{:});
    error('%d of %d unit tests failed:%s', failed, total, failnames);
end

%% -------------------------------------------------------------------------
function banner(txt)
%
% print a section header
%
fprintf(sprintf('%s\n', char(ones(1, 79) * 61)));
fprintf('%s\n', txt);
fprintf(sprintf('%s\n', char(ones(1, 79) * 61)));

%% -------------------------------------------------------------------------
function fname = h5temp(cmd)
%
% return a unique temporary file name, and remember it so that every file can
% be removed at the end of the run. A fixed name would make two concurrent
% test runs overwrite each other's data
%
persistent files

if (isempty(files))
    files = {};
end

if (nargin == 1 && strcmp(cmd, 'cleanup'))
    for i = 1:length(files)
        if (exist(files{i}, 'file'))
            delete(files{i});
        end
    end
    files = {};
    fname = '';
    return
end

fname = [tempname '.h5'];
files{end + 1} = fname;

%% -------------------------------------------------------------------------
function checkroundtrip(testname, val, varargin)
%
% write a value, read it back and compare; any extra arguments are passed to
% both saveh5 and loadh5. jdatadecode restores the types that HDF5 can not
% store natively, such as complex and sparse arrays
%
fname = h5temp();
saveh5(val, fname, 'rootname', 'v', varargin{:});
back = jdatadecode(loadh5(fname, varargin{:}));
if (~isfield(back, 'v'))
    test_easyh5(testname, 'missing root object', 'v');
    return
end
test_easyh5(testname, back.v, val);

%% -------------------------------------------------------------------------
function [rank, dims] = datasetshape(fname, datapath)
%
% report the rank and dimensions of a dataset using the low-level interface,
% which is available both in MATLAB and via the oct-hdf5 package, so that the
% file layout is checked independently of loadh5
%
fid = H5F.open(fname, 'H5F_ACC_RDONLY', 'H5P_DEFAULT');
did = H5D.open(fid, datapath);
sid = H5D.get_space(did);
[rank, dims] = H5S.get_simple_extent_dims(sid);
H5S.close(sid);
H5D.close(did);
H5F.close(fid);

%% -------------------------------------------------------------------------
function isok = hasmethod(cls, name)
%
% whether the HDF5 interface provides a function, such as H5T.get_sign, which
% oct-hdf5 does not
%
isok = true;
try
    % a direct call, as feval does not find static methods in GNU Octave; an
    % existing method fails on the missing arguments instead
    eval([cls '.' name '();']);
catch err
    isok = isempty(regexp(err.message, 'no such method|Unable to resolve|undefined', 'once'));
end

%% -------------------------------------------------------------------------
function isok = hashdf5backend
%
% check whether the low-level HDF5 interface can actually be used; in Octave it
% comes from the oct-hdf5 package and may not be installed
%
isok = true;
try
    probe = [tempname '.h5'];
    saveh5(struct('probe', 1), probe, 'rootname', 'p');
    if (exist(probe, 'file'))
        delete(probe);
    end
catch
    isok = false;
end

%% -------------------------------------------------------------------------
function isok = canusefileid
%
% saveh5 and loadh5 recognise an open file only when it is an H5ML.id, a class
% that exists in MATLAB but not in GNU Octave, where oct-hdf5 uses plain
% numeric identifiers instead
%
isok = false;
try
    probe = [tempname '.h5'];
    fid = H5F.create(probe, 'H5F_ACC_TRUNC', 'H5P_DEFAULT', 'H5P_DEFAULT');
    isok = isa(fid, 'H5ML.id');
    H5F.close(fid);
    if (exist(probe, 'file'))
        delete(probe);
    end
catch
    isok = false;
end

%% -------------------------------------------------------------------------
function isok = candeflate
%
% check whether the HDF5 deflate filter can be configured; it needs
% H5P.set_chunk and H5P.set_deflate, which the oct-hdf5 package does not wrap
%
isok = true;
try
    probe = [tempname '.h5'];
    saveh5(repmat(1:50, 20, 1), probe, 'rootname', 'z', 'Compression', 'deflate');
    if (exist(probe, 'file'))
        delete(probe);
    end
catch
    isok = false;
end
