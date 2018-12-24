import big from 'big.js'
import request from 'superagent'

const FIXED_RATES    = { GRS: 1 }
    , GRS_MSAT_RATIO = big('100000000000')

const enc = encodeURIComponent

// Fetch current exchange rate from Coingecko
// @TODO cache results?
const getRate = currency =>
  request.get(`https://api.coingecko.com/api/v3/simple/price?ids=groestlcoin&vs_currencies=${enc(currency)}`)
    .then(res => res.body.groestlcoin[currency])
    .catch(err => Promise.reject(err.status == 404 ? new Error('Unknown currency: '+currency) : err))

// Convert `amount` units of `currency` to msatoshis
const toMsat = async (currency, amount) =>
  big(amount)
    .div(FIXED_RATES[currency] || await getRate(currency))
    .mul(GRS_MSAT_RATIO)
    .round(0, 3) // round up to nearest msatoshi
    .toFixed(0)

module.exports = { getRate, toMsat }
