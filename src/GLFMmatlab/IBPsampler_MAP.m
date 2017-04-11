function X_map = IBPsampler_MAP(C, Zp, hidden, params)
    % Function to generate the MAP solutions corresponding to patterns in Zp
    % Inputs:
    %   C: 1*D string with data types, D = number of dimensions
    %   Zp: P * K matrix of patterns (P is the number of patterns)
    %   B: latent feature matrix (D * K * maxR)   
    %   T: structure with parameters for mapping function
    %       T.mu: 1*D shift parameter
    %       T.w:  1*D scale parameter
    % Theta: D*maxR matrix where R is the max number of categories
    
    D = size(hidden.B,1);
    P = size(Zp,1);
    K = size(hidden.B,2);
    if (size(Zp,2) ~= K)
        error('Incongruent sizes between Zp and hidden.B');
    end
    
    if ~isempty(params.t{d}) % there is an external transformation
        data.C(d) = params.ext_dataType{d};
    end
    
    X_map = zeros(P,D); % output    
    for d=1:D % for each dimension
        switch C(d)
            case 'g', X_map(:,d) = f_g( Zp * squeeze(hidden.B(d,:,1))', hidden.mu(d), hidden.w(d) );
            case 'p', X_map(:,d) = f_p( Zp * squeeze(hidden.B(d,:,1))', hidden.mu(d), hidden.w(d) );
            case 'n', X_map(:,d) = f_n( Zp * squeeze(hidden.B(d,:,1))', hidden.mu(d), hidden.w(d) );
            case 'c', X_map(:,d) = f_c( Zp * squeeze(hidden.B(d,:,1:hidden.R(d))) );
            case 'o', X_map(:,d) = f_o( Zp * squeeze(hidden.B(d,:,1))', hidden.theta(d,1:(hidden.R(d)-1)) );
            otherwise
                error('Unknown data type');
        end
        if (sum(isnan(X_map(:,d))) > 0)
            warning('Some values are nan!');
        end
        if ~isempty(params.t{d})
            X_map(:,d) = params.t{d}( X_map(:,d) );
        end
    end