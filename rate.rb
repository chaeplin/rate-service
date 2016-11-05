require 'sinatra/base'
#require 'sinatra/json'
require 'json'
require 'bigdecimal'
require 'bigdecimal/util'
require 'pp'
require 'awesome_print'
require 'redis'
require 'byebug'

# Microservice REST API for Dash price to whatever FIAT currency, and BTC.
#
# Input: FX Pair
# Output: Returns exchange rate
#
# Future: Stick this into a DB/Redis, pull rate every X seconds. Then write out
# static files for each currency pair and serve up JSON files directly via
# nginx. This should scale like crazy.

# TODO: separate exchange rate logic & sinatra service
# TODO: ensure BigDecimal used throughout here, from input on...
#       output should use: d.round(8).to_s('8F')


def make_payload(h)
  payload = {}

  if h.has_key?(:err)
    payload = { success: false, error: h[:err] }
  else
    payload = { success: true, quote: h[:pair], rate: h[:rate].round(8).to_s('8F') }
  end

  return payload.to_json
end


# fetch the rate info from DB, calculate & return
def get_rates(fxpair)
  base, quote = fxpair.split /_/

  # standardize any inconsistencies in currency ticker names
  base  = normalize_ticker_string(base)
  quote = normalize_ticker_string(quote)
  fxpair = base + '_' + quote

  # check validity of base/quote
  if (not is_valid_ticker_string(base))
    return make_payload(err: "#{base} is not a valid currency ticker string")
  end
  if (not is_valid_ticker_string(quote))
    return make_payload(err: "#{quote} is not a valid currency ticker string")
  end


  # do the thing
  if (base === quote)
    payload = make_payload(pair: fxpair, rate: BigDecimal.new(1))

  elsif (is_fiat(base))
    payload = make_payload(err: 'Fiat base pairs are not supported.')

  elsif (poloniex_has_pair(fxpair))
    payload = make_payload(pair: fxpair, rate: poloniex_pair(fxpair))

  elsif (is_crypto(quote) && is_crypto(base))
    # in this case, both are alt crypto.
    # get BTC_<alt> rate for each & divide...
    base_rate  = poloniex_pair(base + '_BTC').to_d
    quote_rate = poloniex_pair(quote + '_BTC').to_d
    rate = base_rate * (1.0 / quote_rate)
    payload = make_payload(pair: fxpair, rate: rate)

  elsif (is_fiat(quote))
    if (base === 'BTC')
      rate = btc_fiat_rate(quote)
    else
      rate = poloniex_pair(base + '_BTC') * btc_fiat_rate(quote)
    end
    payload = make_payload(pair: fxpair, rate: rate)

  else
    payload = make_payload(err: "FX Pair [#{fxpair}] unsupported.")
  end

  return payload
end


class RateService < Sinatra::Base
  set :port, 4568
  redis = Redis.new

  before do
    content_type :json
  end

  # /rate/:fxpair(.ext)?
  get '/rate/:fxpair.?:format?' do
    puts "my env: [#{settings.environment}]"
    return get_rates(params[:fxpair].strip.upcase)
  end

  get '/*' do
    return make_payload(err: "Sorry, that path is not defined.")
  end

  # $0 is the executed file
  # __FILE__ is the current file
  run! if __FILE__ == $0
end
