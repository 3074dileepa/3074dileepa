#!/bin/bash

# Update and install required packages
sudo apt-get update
sudo apt-get install -y tor nodejs npm libx11-xcb1 libxtst6 libxrandr2 libgtk-3-0 libnss3 libasound2 libatk-bridge2.0-0 libxss1 libgbm1

# Start Tor service
sudo service tor start

# Wait for Tor to start
echo "Waiting for Tor to start..."
sleep 10

# Install Puppeteer
npm install puppeteer

# Create the Puppeteer script
cat <<'EOF' > continuous_visit_puppeteer.js
const puppeteer = require('puppeteer');
const { execSync } = require('child_process');

function randomVisitDuration() {
  return Math.floor(Math.random() * (35 - 30 + 1) + 30) * 60 * 1000;
}

async function fetchIP(proxy = false) {
  const args = proxy ? ['--proxy-server=socks5://127.0.0.1:9050'] : [];
  const browser = await puppeteer.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--incognito', ...args],
  });
  const page = await browser.newPage();
  try {
    await page.goto('https://icanhazip.com', { waitUntil: 'domcontentloaded', timeout: 30000 });
    const ip = await page.evaluate(() => document.body.innerText.trim());
    console.log(proxy ? 'IP after Tor: ' : 'IP before Tor: ', ip);
    return ip;
  } catch (error) {
    console.error('Failed to fetch IP:', error.message);
    return null;
  } finally {
    await browser.close();
  }
}

async function restartTor() {
  console.log('Restarting Tor...');
  execSync('sudo service tor stop');
  execSync('sudo service tor start');
  console.log('Waiting for Tor to restart...');
  await new Promise((resolve) => setTimeout(resolve, 30000));
}

async function fetchIPWithTorRetry() {
  let ip = null;
  while (!ip) {
    ip = await fetchIP(true);
    if (!ip) {
      await restartTor();
    }
  }
}

async function visitWebsite(url) {
  const browser = await puppeteer.launch({
    headless: true,
    args: [
      '--proxy-server=socks5://127.0.0.1:9050',
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--incognito',
      '--js-flags=--optimize-for-size --max-old-space-size=4096',
    ],
  });
  const page = await browser.newPage();
  let loaded = false;
  while (!loaded) {
    try {
      await page.goto(url, { waitUntil: 'domcontentloaded' });
      loaded = true;
      const title = await page.title();
      console.log('Page title:', title);
    } catch (error) {
      console.error('Page load failed, restarting Tor:', error.message);
      await restartTor();
    }
  }

  const checkHashesPerSecond = setInterval(async () => {
    try {
      const hashesPerSecond = await page.evaluate(() => {
        const element = document.querySelector('#hps');
        return element
          ? element.textContent.replace('Hashes per second: ', '').trim()
          : 'Element not found';
      });
      console.log('Hashes per second:', hashesPerSecond);
    } catch (error) {
      console.error('Error fetching Hashes per second:', error.message);
    }
  }, 20000);

  const visitDuration = randomVisitDuration();
  console.log('Staying on the website for', visitDuration / 60000, 'minutes...');
  await new Promise((resolve) => setTimeout(resolve, visitDuration));
  clearInterval(checkHashesPerSecond);
  await browser.close();
  execSync('sudo service tor stop');
  console.log('Tor stopped after visiting the website.');
}

async function randomWait() {
  const waitTime = Math.floor(Math.random() * (5 - 2 + 1) + 2) * 60 * 1000;
  console.log('Waiting for', waitTime / 60000, 'minutes before next visit...');
  await new Promise((resolve) => setTimeout(resolve, waitTime));
}

async function fetchIPsAndVisit() {
  const endTime = Date.now() + 5 * 60 * 60 * 1000;
  await fetchIP(false);
  await fetchIPWithTorRetry();
  while (Date.now() < endTime) {
    execSync('sudo service tor start');
    console.log('Tor started before visiting the website.');
    await fetchIP(true);
    await visitWebsite('https://dileepa11.netlify.app/');
    await randomWait();
  }
  console.log('Completed 5-hour cycle, stopping now.');
}

fetchIPsAndVisit();
EOF

# Run the Puppeteer script
node continuous_visit_puppeteer.js
