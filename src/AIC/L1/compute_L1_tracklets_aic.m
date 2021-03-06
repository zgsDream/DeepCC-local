function compute_L1_tracklets_aic(opts)
    % Computes tracklets for all cameras
    if opts.tracklets.og_appear_score
        appear_model_param = [];
    else
        appear_model_param = load(fullfile('src','hyper_score/logs',opts.appear_model_name));
    end
    if opts.tracklets.og_motion_score
        motion_model_param = [];
    else
        motion_model_param = load(fullfile('src','hyper_score/logs',opts.motion_model_name));
    end
    for scene = opts.seqs{opts.sequence}
    opts.current_scene = scene;
    for i = 1:length(opts.cams_in_scene{scene})
        iCam = opts.cams_in_scene{scene}(i);
        opts.current_camera = iCam;

        % Load OpenPose detections for current camera
        detections      = load(sprintf('%s/%s/S%02d/c%03d/det/det_%s_gps.txt', opts.dataset_path, opts.sub_dir{opts.sequence}, scene, iCam, opts.detections));
        start_frame     = detections(1, 1);
        end_frame       = detections(end, 1);
        
%         imageROI        = imread(sprintf('%s/%s/S%02d/c%03d/roi.jpg', opts.dataset_path, opts.sub_dir{opts.sequence}, scene, iCam));
        imageROI        = imread(sprintf('%s/ROIs/background/S%02d/c%02d.png', opts.dataset_path, scene, iCam));
        if length(size(imageROI)) >2
            imageROI        = rgb2gray(imageROI);
            imageROI        = imbinarize(imageROI,1-10^-12);
        end
        
        % Load features for all detections
        if isempty(opts.feature_dir)
            features    = h5read(sprintf('%s/L0-features/features%d.h5',opts.dataset_path,iCam),'/emb');
        else
            features    = h5read(sprintf('%s/L0-features/%s/features%d.h5',opts.dataset_path,opts.feature_dir,iCam),'/emb');
        end

        in_time_range_ids = detections(:,1)>=start_frame & detections(:,1)<=end_frame;
        all_dets   = detections(in_time_range_ids,:);

        if size(features,2) == size(detections,1)
            features = features(3:end,in_time_range_ids);
        else
            features = features(3:end,features(2,:)>=start_frame & features(2,:)<=end_frame);
        end
        
        assert(size(features,2) == size(detections,1))

        appearance = cell(size(all_dets,1),1);
        frames     = cell(size(all_dets,1),1);

        for k = 1:length(frames)
            appearance{k} = double(features(:,k)');
            frames{k} = detections(k,1);
        end

        % Compute tracklets for every 1-second interval
        tracklets = struct([]);

        for window_start_frame   = start_frame : opts.tracklets.window_width : end_frame
            fprintf('%d/%d\n', window_start_frame, end_frame);

            % Retrieve detections in current window
            window_end_frame     = window_start_frame + opts.tracklets.window_width - 1;
            window_frames        = window_start_frame : window_end_frame;
            window_inds          = find(ismember(all_dets(:,1),window_frames));
            detections_in_window = all_dets(window_inds,:);
            % num_visible          = sum(detections_in_window(:,7)> opts.render_threshold, 2);

            % Use only valid detections
            valid                           = getAICValidDetections(iCam, detections_in_window, imageROI);
            detections_in_window            = detections_in_window(valid, :);
            if opts.dataset == 2
                detections_in_window(:,7:8) = detections_in_window(:,10:11);
            end
            detections_in_window(:,9:end)   = [];
            detections_in_window(:,[2 1])   = [ones(size(detections_in_window,1),1)*iCam,detections_in_window(:,1)];
            filteredDetections              = detections_in_window;
            filteredFeatures                = [];
            filteredFeatures.appearance     = appearance(window_inds(valid));

            % Compute tracklets in current window
            % Then add them to the list of all tracklets
            tracklets = createTracklets(opts, filteredDetections, filteredFeatures, window_start_frame, window_end_frame, tracklets,appear_model_param,motion_model_param,iCam);
        end

        % Save tracklets
        save(sprintf('%s/%s/L1-tracklets/tracklets%d_%s.mat', ...
            opts.experiment_root, ...
            opts.experiment_name, ...
            iCam, ...
            opts.folder_by_seq{opts.sequence}), ...
            'tracklets');

        % Clean up
        clear all_dets appearance detections features frames

    end
    end
end

