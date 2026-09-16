%% preprocess_NASA_B0006.m
% Preprocess NASA PCoE B0006 lithium-ion battery dataset.
%
% Output:
%   B0006_processed.csv
% Columns:
%   SampleID          - paired charge-discharge sample index
%   ChargeCycleIndex  - original charge-cycle index in B0006.cycle
%   DischargeCycleIndex - original discharge-cycle index in B0006.cycle
%   PC_time_CC        - duration of constant-current charging stage (s)
%   PC_time_CV        - duration of constant-voltage charging stage (s)
%   Capacity_HI       - discharge capacity used as health indicator (Ah)
%
% Pairing rule:
%   Each valid charge cycle is paired with the next valid discharge cycle.
%
% Feature definition used here:
%   CC stage: from the beginning of charging to the first time the charging
%             voltage reaches the CV transition threshold.
%   CV stage: from the CC/CV transition to the first time the charging
%             current falls below the termination-current threshold.
%
% IMPORTANT:
%   The thresholds below are centralized so they can be changed to match
%   the exact protocol used in the manuscript.
%
% Typical NASA B0006 charging protocol:
%   constant-current charging at about 1.5 A until ~4.2 V, followed by
%   constant-voltage charging until current decreases to about 20 mA.
%
% Author: generated for RE-BRB reproducibility

clear; clc;

%% ====================== User configuration =============================
MAT_FILE = 'B0006.mat';
OUT_CSV  = 'B0006_processed.csv';

% Thresholds for stage segmentation.
CV_START_VOLTAGE = 4.20;    % V, transition from CC to CV
VOLTAGE_TOL      = 0.02;    % V, tolerance for detecting CV start
CV_END_CURRENT   = 0.020;   % A, charge termination current
CURRENT_TOL      = 0.005;   % A, tolerance for detecting CV end

% Optional sanity check based on the manuscript dataset size.
EXPECTED_SAMPLES = 166;

%% =========================== Load data =================================
if ~isfile(MAT_FILE)
    error('Cannot find %s in the current folder.', MAT_FILE);
end

S = load(MAT_FILE);

% NASA files normally contain a top-level structure named B0006.
if isfield(S, 'B0006')
    batt = S.B0006;
else
    fn = fieldnames(S);
    if numel(fn) == 1 && isstruct(S.(fn{1}))
        batt = S.(fn{1});
        warning('Top-level variable is "%s" rather than "B0006".', fn{1});
    else
        error('Cannot identify the battery structure in %s.', MAT_FILE);
    end
end

if ~isfield(batt, 'cycle')
    error('The battery structure does not contain the field "cycle".');
end

cycles = batt.cycle;
nCycles = numel(cycles);

%% ==================== Traverse and pair cycles =========================
rows = [];
sampleID = 0;

i = 1;
while i <= nCycles

    if ~isfield(cycles(i), 'type') || ~strcmpi(strtrim(cycles(i).type), 'charge')
        i = i + 1;
        continue;
    end

    chargeIdx = i;

    % Find the next discharge cycle after this charge cycle.
    dischargeIdx = [];
    j = i + 1;
    while j <= nCycles
        if isfield(cycles(j), 'type')
            thisType = strtrim(cycles(j).type);

            if strcmpi(thisType, 'discharge')
                dischargeIdx = j;
                break;
            elseif strcmpi(thisType, 'charge')
                % A new charge begins before a discharge is found.
                % Do not cross-pair across two charge cycles.
                break;
            end
        end
        j = j + 1;
    end

    if isempty(dischargeIdx)
        i = i + 1;
        continue;
    end

    chargeData    = cycles(chargeIdx).data;
    dischargeData = cycles(dischargeIdx).data;

    % Extract one paired sample.
    [pcTimeCC, pcTimeCV, okCharge] = extract_charge_features( ...
        chargeData, CV_START_VOLTAGE, VOLTAGE_TOL, ...
        CV_END_CURRENT, CURRENT_TOL);

    [capacityHI, okCapacity] = extract_capacity(dischargeData);

    if okCharge && okCapacity
        sampleID = sampleID + 1;
        rows(sampleID, :) = [ ...
            sampleID, chargeIdx, dischargeIdx, ...
            pcTimeCC, pcTimeCV, capacityHI]; %#ok<SAGROW>
    else
        fprintf(['Skipped pair: charge cycle %d, discharge cycle %d ', ...
                 '(valid_charge=%d, valid_capacity=%d)\n'], ...
                 chargeIdx, dischargeIdx, okCharge, okCapacity);
    end

    % Continue after the paired discharge cycle.
    i = dischargeIdx + 1;
end

%% =========================== Save output ================================
if isempty(rows)
    error('No valid charge-discharge samples were extracted.');
end

T = array2table(rows, 'VariableNames', { ...
    'SampleID', ...
    'ChargeCycleIndex', ...
    'DischargeCycleIndex', ...
    'PC_time_CC', ...
    'PC_time_CV', ...
    'Capacity_HI'});

writetable(T, OUT_CSV);

fprintf('\n============================================================\n');
fprintf('NASA B0006 preprocessing completed.\n');
fprintf('Valid paired samples : %d\n', height(T));
fprintf('Output file          : %s\n', OUT_CSV);
fprintf('PC-time-CC range     : %.3f -- %.3f s\n', ...
    min(T.PC_time_CC), max(T.PC_time_CC));
fprintf('PC-time-CV range     : %.3f -- %.3f s\n', ...
    min(T.PC_time_CV), max(T.PC_time_CV));
fprintf('Capacity range       : %.6f -- %.6f Ah\n', ...
    min(T.Capacity_HI), max(T.Capacity_HI));

if ~isempty(EXPECTED_SAMPLES) && height(T) ~= EXPECTED_SAMPLES
    warning(['Extracted %d valid samples, while EXPECTED_SAMPLES=%d. ', ...
             'Check the raw B0006 version and stage thresholds if your ', ...
             'manuscript uses exactly %d samples.'], ...
             height(T), EXPECTED_SAMPLES, EXPECTED_SAMPLES);
end

%% ======================== Optional normalization ========================
% The following code is intentionally commented out.
% If the RE-BRB experiment uses min-max normalized inputs, fit the
% normalization parameters ONLY on the training set to avoid data leakage.
%
% X = T{:, {'PC_time_CC','PC_time_CV'}};
% y = T.Capacity_HI;
%
% Example chronological split matching 116/50 when N=166:
% nTrain = 116;
% Xtrain = X(1:nTrain,:);
% Xtest  = X(nTrain+1:end,:);
% ytrain = y(1:nTrain);
% ytest  = y(nTrain+1:end);
%
% xmin = min(Xtrain, [], 1);
% xmax = max(Xtrain, [], 1);
% XtrainN = (Xtrain - xmin) ./ max(xmax - xmin, eps);
% XtestN  = (Xtest  - xmin) ./ max(xmax - xmin, eps);

%% =========================== Functions =================================
function [pcTimeCC, pcTimeCV, ok] = extract_charge_features( ...
    data, cvVoltage, vTol, cvEndCurrent, iTol)

    pcTimeCC = NaN;
    pcTimeCV = NaN;
    ok = false;

    % ---- Time vector ----
    if ~isfield(data, 'Time') || isempty(data.Time)
        return;
    end
    t = double(data.Time(:));

    % ---- Voltage signal ----
    if isfield(data, 'Voltage_measured') && ~isempty(data.Voltage_measured)
        v = double(data.Voltage_measured(:));
    elseif isfield(data, 'Voltage_charge') && ~isempty(data.Voltage_charge)
        v = double(data.Voltage_charge(:));
    else
        return;
    end

    % ---- Current signal ----
    if isfield(data, 'Current_measured') && ~isempty(data.Current_measured)
        current = abs(double(data.Current_measured(:)));
    elseif isfield(data, 'Current_charge') && ~isempty(data.Current_charge)
        current = abs(double(data.Current_charge(:)));
    else
        return;
    end

    % Make all signals the same length and remove non-finite values.
    n = min([numel(t), numel(v), numel(current)]);
    t = t(1:n);
    v = v(1:n);
    current = current(1:n);

    valid = isfinite(t) & isfinite(v) & isfinite(current);
    t = t(valid);
    v = v(valid);
    current = current(valid);

    if numel(t) < 3
        return;
    end

    % Ensure monotonically increasing time.
    [t, order] = sort(t);
    v = v(order);
    current = current(order);

    % Remove duplicate time stamps if present.
    [t, uniqueIdx] = unique(t, 'stable');
    v = v(uniqueIdx);
    current = current(uniqueIdx);

    if numel(t) < 3
        return;
    end

    % ---- Detect CC -> CV transition ----
    % First point where voltage reaches the upper-charge threshold.
    idxCVStart = find(v >= (cvVoltage - vTol), 1, 'first');

    if isempty(idxCVStart)
        % Fallback: use the point nearest to the target voltage.
        [~, idxCVStart] = min(abs(v - cvVoltage));
    end

    % Avoid degenerate transition at the very first/last point.
    idxCVStart = max(2, min(idxCVStart, numel(t)-1));

    % ---- Detect end of CV stage ----
    % First point after CV starts where current reaches termination level.
    idxLocal = find(current(idxCVStart:end) <= ...
                    (cvEndCurrent + iTol), 1, 'first');

    if isempty(idxLocal)
        % Some file versions may end before reaching the nominal current.
        % In that case, use the last available charging point.
        idxCVEnd = numel(t);
    else
        idxCVEnd = idxCVStart + idxLocal - 1;
    end

    % Guard against numerical/pathological cases.
    if idxCVEnd <= idxCVStart
        idxCVEnd = numel(t);
    end

    % ---- Charging-stage durations ----
    pcTimeCC = t(idxCVStart) - t(1);
    pcTimeCV = t(idxCVEnd)   - t(idxCVStart);

    ok = isfinite(pcTimeCC) && isfinite(pcTimeCV) && ...
         pcTimeCC > 0 && pcTimeCV >= 0;
end

function [capacity, ok] = extract_capacity(data)

    capacity = NaN;
    ok = false;

    % NASA B0006 discharge cycles normally provide capacity directly.
    if isfield(data, 'Capacity') && ~isempty(data.Capacity)
        c = double(data.Capacity(:));
        c = c(isfinite(c));

        if ~isempty(c)
            capacity = c(1);
            ok = capacity > 0;
            return;
        end
    end

    % Fallback: estimate discharge capacity by integrating measured current.
    % This branch is only used if Capacity is absent.
    if isfield(data, 'Time') && ...
       isfield(data, 'Current_measured') && ...
       ~isempty(data.Time) && ~isempty(data.Current_measured)

        t = double(data.Time(:));
        current = abs(double(data.Current_measured(:)));

        n = min(numel(t), numel(current));
        t = t(1:n);
        current = current(1:n);

        valid = isfinite(t) & isfinite(current);
        t = t(valid);
        current = current(valid);

        if numel(t) >= 2
            [t, order] = sort(t);
            current = current(order);
            capacity = trapz(t, current) / 3600;  % Ah
            ok = isfinite(capacity) && capacity > 0;
        end
    end
end
