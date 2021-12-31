module AdaptiveWindow

export AdaptiveMean, fit!, mean, value, nobs, stats, withoutdropping

import StatsBase: nobs, fit!, merge!
import OnlineStatsBase: value, OnlineStat, Variance, Mean, _fit!

#=
 Adaptive Windowing version 2 (AdaptiveMean2)

    Used to track the mean value of a stream of data with a possibly changing population.
    If the population is determined to be changed, older observations will be dropped

  Bifet and Gavalda. Learning from Time-Changing Data with Adaptive Windowing
=#

    # Bifet and Gavalda: We use, somewhat arbitrarily, M = 5 for all experiments.
    const M = 5

    default_detect(ad) = nothing

    mutable struct AdaptiveMean <: OnlineStat{Number}
        
        δ ::Float64
        window::Array{Variance, 1}
        stats ::Variance
        
        onshiftdetect

        AdaptiveMean(;δ = 0.001, onshiftdetected = default_detect) = new(δ, fill(Variance(), M), Variance(), onshiftdetected)    
    end

    function _fit!(ad::AdaptiveMean, value)
        fit!(ad.window[1], value)
        fit!(ad.stats, value)
    
        compress!(ad)
        if dropifdrifting!(ad)
            ad.onshiftdetect(ad)
        end
        ad
    end

    nobs(ad::AdaptiveMean) = ad.stats.n
    stats(ad::AdaptiveMean) = ad.stats

    function mean(ad::AdaptiveMean)
        ad.stats.μ
    end

    function value(ad::AdaptiveMean)
        mean(ad)
    end
                
    function compress!(ad::AdaptiveMean)
        makespace!(ad, 1, 1.0);
    end
    
    function makespace!(ad::AdaptiveMean, start::Int, max::Float64)
    #=
        The window is a gappy list of data points, this avoids allocations and reallocations 
        when the window resizes
    
        Assume M = 3, the lists below show the counts of observations
    
            Entry: [1, 0, 0],               Exit: [0, 1, 0]
            Entry: [1, 1, 0],               Exit: [0, 1, 1]
            Entry: [1, 1, 1],               Exit: [0, 1, 1, 1, 0, 0]
            Entry [1, 1, 1, 1, 0, 0],       Exit: [0, 1, 1, 0, 2, 0]
            Entry [1, 1, 1, 0, 2, 0],       Exit: [0, 1, 1, 1, 2, 0]
            Entry [1, 1, 1, 1, 2, 0],       Exit: [0, 1, 1, 0, 2, 2]
            Entry [1, 1, 1, 0, 2, 2],       Exit: [0, 1, 1, 1, 2, 2]
            Entry [1, 1, 1, 1, 2, 2],       Exit: [0, 1, 1, 0, 2, 2, 2, 0, 0]
    
    =#
    
        if nobs(ad.window[start]) < max
            return
        end
    
        # Move-to-front: [a, b, c] -> [c, a, b]
        lastEntryInRange = start + M - 1;
        lastStats = ad.window[lastEntryInRange];
        for j in lastEntryInRange:-1:start+1
            ad.window[j] = ad.window[j-1];
        end
        ad.window[start] = lastStats
    
        if nobs(ad.window[start]) != 0
            next = start + M
            if length(ad.window) < next
                for i in 1:M
                    push!(ad.window, Variance())
                end
            end
    
            merge!(ad.window[next], lastStats)
            ad.window[start] = Variance()
            makespace!(ad, next, max*2)
        end
    end

    function tomean(v::Variance)
        mean = Mean()
        mean.n = v.n 
        mean.μ = v.μ
        mean 
    end 

    function _remove!(m::Mean, v::Variance)
        residualsum = m.μ * m.n - v.μ * v.n
        m.n -= v.n 
        m.μ = residualsum / m.n 
        m
    end
       
    function _merge!(m::Mean, v::Variance)
        merge!(m, tomean(v))
    end

    function dropifdrifting!(ad::AdaptiveMean)
    
        statsToRight = tomean(ad.stats)
        statsToLeft = Mean()
    
        deltaPrime = ad.δ / log(nobs(ad.stats))
        logDeltaPrime = log(2/deltaPrime)
        variance = value(ad.stats)
    
        for i in 2:length(ad.window)
            if nobs(ad.window[i]) == 0
                continue
            end
    
            _remove!(statsToRight, ad.window[i])
            _merge!(statsToLeft, ad.window[i])

            #statsToRight -= toMean(ad.window[i]);
            #statsToLeft  += toMean(ad.window[i]);
    
            if statsToRight.n < 1e-9
                break # only zeros from this point on
            end
    
            mInv = 1.0/ statsToRight.n + 1.0/ statsToLeft.n;
    
            epsCut =sqrt(2 * mInv * variance * logDeltaPrime) + 2.0/3.0 * mInv * logDeltaPrime;
    
            if abs(statsToRight.μ - statsToLeft.μ) > epsCut
                # Drift detected, clear all from here on
                for j = i+1:length(ad.window)
                    ad.window[j] = Variance()
                end
                ad.stats = Variance()
                for stat in 1:i
                    merge!(ad.stats, ad.window[stat])
                end
                return true
            end
        end
    
        return false
    end
    

    struct Wrapper <: OnlineStat{Number}
        ad::AdaptiveMean
    end

    withoutdropping(ad::AdaptiveMean) = Wrapper(ad)

    function _fit!(wrap::Wrapper, value)
        ad = wrap.ad 
        fit!(ad.window[1], value)
        fit!(ad.stats, value)
    
        compress!(ad)   
        wrap
    end

    nobs(wrap::Wrapper) = nobs(wrap.ad)

end # module
