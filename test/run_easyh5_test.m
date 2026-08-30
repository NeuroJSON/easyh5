function run_easyh5_test(tests)
%
% run_easyh5_test
%   or
% run_easyh5_test(tests)
% run_easyh5_test({'basic', 'types', 'struct', 'shape', 'opt', 'handle'})
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
    tests = {'basic', 'types', 'struct', 'shape', 'opt', 'handle'};
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
