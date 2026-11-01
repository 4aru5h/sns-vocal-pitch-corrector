% RUN_TESTS Test runner for vocal pitch correction project
addpath(fullfile(pwd, 'src'));
results = runtests('tests');
disp(table(results));
assertSuccess(results);
