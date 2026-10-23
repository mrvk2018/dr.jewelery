/**
 * Перезаливка «фото 0» (Articuls.Image → {sku}.webp) для active-товаров
 * со старым .jpg в image_url / images[0].
 *
 *   npm run sync:photo0
 *   npm run sync:photo0 -- --all-active   # все active, не только .jpg
 */

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

process.argv.push('--resync-photo0');
require('../sync.js');
