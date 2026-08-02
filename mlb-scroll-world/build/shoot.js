// Drive the page in real Chrome and screenshot the flight at fixed scroll
// depths. Confirms the engine mounts, the clips decode and paint, and the copy
// lands where it should — none of which the asset checks can tell us.
const puppeteer = require('puppeteer-core');

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const URL = process.env.URL || 'http://127.0.0.1:8777/index.html';
const OUT = process.env.OUT || 'build/shots';
const STOPS = (process.env.STOPS || '0,0.06,0.13,0.20,0.28,0.36,0.45,0.54,0.63,0.72,0.82,0.93')
  .split(',').map(Number);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: 'shell',
    args: ['--autoplay-policy=no-user-gesture-required', '--mute-audio',
           '--window-size=1440,900'],
  });
  const page = await browser.newPage();
  await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 1 });

  const errors = [];
  page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));
  page.on('requestfailed', (r) => errors.push(`failed: ${r.url()} ${r.failure()?.errorText}`));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(`console: ${m.text()}`); });

  await page.goto(URL, { waitUntil: 'networkidle2', timeout: 60000 });

  const height = await page.evaluate(() => document.body.scrollHeight);
  const vh = await page.evaluate(() => window.innerHeight);
  console.log(`track height ${height}px  = ${(height / vh).toFixed(1)} viewport heights`);

  // MODE=sections parks the camera at each scene's midpoint — where the engine
  // is designed to hold the copy at full opacity — instead of arbitrary depths.
  const sections = process.env.MODE === 'sections';
  const count = await page.evaluate(() => document.querySelectorAll('.sw-route__dot').length);
  const stops = sections ? [...Array(count).keys()] : STOPS;

  for (const [i, frac] of stops.entries()) {
    let y;
    if (sections) {
      await page.evaluate((n) => {
        document.querySelectorAll('.sw-route__dot')[n].click();
      }, frac);
      await sleep(2200);                       // route dots scroll smoothly
      y = await page.evaluate(() => Math.round(window.scrollY));
    } else {
      y = Math.round((height - vh) * frac);
      await page.evaluate((top) => window.scrollTo({ top, behavior: 'instant' }), y);
    }
    // Let the engine lerp toward its target and the decoder land the seek.
    await sleep(1400);
    const state = await page.evaluate(() => {
      const vids = [...document.querySelectorAll('.sw-scene__video')];
      const painted = [...document.querySelectorAll('.sw-scene.has-clip')].length;
      const active = document.querySelector('.sw-nav__item.is-active');
      const copy = [...document.querySelectorAll('.sw-copy')]
        .map((c) => +getComputedStyle(c).opacity);
      return {
        loaded: vids.length,
        painted,
        readyStates: vids.map((v) => v.readyState).join(''),
        active: active ? active.textContent : null,
        topCopy: Math.max(...copy).toFixed(2),
      };
    });
    const name = `${OUT}/stop-${String(i).padStart(2, '0')}-${frac}.png`;
    await page.screenshot({ path: name });
    console.log(`${frac.toString().padEnd(5)} y=${String(y).padEnd(6)} `
      + `clips=${state.loaded} painted=${state.painted} `
      + `ready=${state.readyStates} nav=${state.active} copy=${state.topCopy}`);
  }

  console.log(errors.length ? `\nISSUES:\n${errors.join('\n')}` : '\nno page errors');
  await browser.close();
})();
