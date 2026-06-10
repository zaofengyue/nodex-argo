// ========== 预留配置，留空则自动识别 ==========
const PRESET_UUID        = '';
const PRESET_TROJAN_PASS = '';
const PRESET_PORT        = '';
const PRESET_ARGO_PORT   = '';
const PRESET_NAME        = '';
const PRESET_SUB         = '';
const PRESET_ARGO_DOMAIN = '';
const PRESET_ARGO_AUTH   = '';
// =============================================

const { execSync, spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const https = require('https');
const http = require('http');
const crypto = require('crypto');
const net = require('net');

const HOME = process.env.HOME || '/tmp';
const UUID_FILE = `${HOME}/uuid.txt`;
const TROJAN_FILE = `${HOME}/trojan.txt`;
const CONFIG_FILE = `${HOME}/xray-config.json`;
const XRAY_DIR = `${HOME}/xray`;
const XRAY_BIN_PATH = `${XRAY_DIR}/xray`;
const CLOUDFLARED_BIN = `${HOME}/cloudflared`;
const WS_PATH_VMESS  = '/fengyue-vm';
const WS_PATH_VLESS  = '/fengyue-vl';
const WS_PATH_TROJAN = '/fengyue-tr';
const V_VMESS_PORT  = 10000;
const V_VLESS_PORT  = 10001;
const V_TROJAN_PORT = 10002;
const CF_PREFER_HOST = 'cdns.doon.eu.org';

function getFreePort() {
  return new Promise((resolve) => {
    const srv = net.createServer();
    srv.listen(0, '127.0.0.1', () => {
      const port = srv.address().port;
      srv.close(() => resolve(port));
    });
  });
}

function httpGet(url, timeout = 5000) {
  return new Promise((resolve) => {
    const req = https.get(url, { timeout }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve(data.trim()));
    });
    req.on('error', () => resolve(''));
    req.on('timeout', () => { req.destroy(); resolve(''); });
  });
}

function download(url, dest) {
  try { execSync(`curl -sL "${url}" -o "${dest}"`); return; } catch {}
  try { execSync(`wget -q "${url}" -O "${dest}"`); return; } catch {}
  throw new Error(`下载失败: ${url}`);
}

async function downloadXray() {
  if (fs.existsSync(XRAY_BIN_PATH)) return XRAY_BIN_PATH;

  const arch = os.arch();
  const archMap = {
    'x64': 'linux-64',
    'arm64': 'linux-arm64-v8a',
    'arm': 'linux-arm32-v7a'
  };
  const platform = archMap[arch] || 'linux-64';

  console.log(`正在下载 xray (${platform})...`);

  const release = await httpGet('https://api.github.com/repos/XTLS/Xray-core/releases/latest');
  let version = 'v25.4.30';
  try { version = JSON.parse(release).tag_name || version; } catch {}

  const url = `https://github.com/XTLS/Xray-core/releases/download/${version}/Xray-${platform}.zip`;
  fs.mkdirSync(XRAY_DIR, { recursive: true });
  download(url, `${HOME}/xray.zip`);
  execSync(`unzip -qo "${HOME}/xray.zip" -d "${XRAY_DIR}" && chmod +x "${XRAY_BIN_PATH}"`);
  console.log('xray 下载完成');
  return XRAY_BIN_PATH;
}

async function downloadCloudflared() {
  if (fs.existsSync(CLOUDFLARED_BIN)) {
    execSync(`chmod +x "${CLOUDFLARED_BIN}"`);
    return CLOUDFLARED_BIN;
  }

  const arch = os.arch();
  const archMap = {
    'x64': 'linux-amd64',
    'arm64': 'linux-arm64',
    'arm': 'linux-arm'
  };
  const platform = archMap[arch] || 'linux-amd64';

  console.log(`正在下载 cloudflared (${platform})...`);
  const url = `https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-${platform}`;
  download(url, CLOUDFLARED_BIN);
  execSync(`chmod +x "${CLOUDFLARED_BIN}"`);
  console.log('cloudflared 下载完成');
  return CLOUDFLARED_BIN;
}

function startArgoTunnel(cfBin, argoPort, argoDomain, argoAuth) {
  return new Promise((resolve) => {
    let argoHost = '';
    let args;

    if (argoDomain && argoAuth) {
      console.log('启动固定 Argo 隧道...');
      args = ['tunnel', '--edge-ip-version', 'auto', '--no-autoupdate',
              'run', '--token', argoAuth];
      argoHost = argoDomain;
      const cf = spawn(cfBin, args, { stdio: 'pipe' });
      cf.on('error', (err) => console.error('cloudflared error:', err));
      setTimeout(() => resolve(argoHost), 3000);
    } else {
      console.log('启动临时 Argo 隧道...');
      args = ['tunnel', '--edge-ip-version', 'auto', '--no-autoupdate',
              '--url', `http://127.0.0.1:${argoPort}`];
      const cf = spawn(cfBin, args, { stdio: 'pipe' });

      cf.stderr.on('data', (data) => {
        const str = data.toString();
        const match = str.match(/https:\/\/([a-z0-9-]+\.trycloudflare\.com)/);
        if (match && !argoHost) {
          argoHost = match[1];
          console.log(`临时隧道域名: ${argoHost}`);
          resolve(argoHost);
        }
      });

      cf.on('error', (err) => console.error('cloudflared error:', err));

      setTimeout(() => {
        if (!argoHost) {
          console.log('临时隧道域名获取超时');
          resolve('');
        }
      }, 30000);
    }
  });
}

async function main() {
  let UUID = PRESET_UUID || process.env.UUID || '';
  if (UUID) {
    fs.writeFileSync(UUID_FILE, UUID);
  } else if (fs.existsSync(UUID_FILE)) {
    UUID = fs.readFileSync(UUID_FILE, 'utf8').trim();
  } else {
    UUID = crypto.randomUUID();
    fs.writeFileSync(UUID_FILE, UUID);
  }

  let TROJAN_PASS = PRESET_TROJAN_PASS || process.env.TROJAN_PASS || '';
  if (TROJAN_PASS) {
    fs.writeFileSync(TROJAN_FILE, TROJAN_PASS);
  } else if (fs.existsSync(TROJAN_FILE)) {
    TROJAN_PASS = fs.readFileSync(TROJAN_FILE, 'utf8').trim();
  } else {
    TROJAN_PASS = crypto.randomBytes(16).toString('hex');
    fs.writeFileSync(TROJAN_FILE, TROJAN_PASS);
  }

  // 对外端口：预设 → 平台注入 → 自动找空闲端口
  const INBOUND_PORT = PRESET_PORT
    ? parseInt(PRESET_PORT)
    : process.env.PORT
      ? parseInt(process.env.PORT)
      : await getFreePort();

  const SUB_RAW = PRESET_SUB || process.env.SUB || 'sub';
  const SUB_PATH = '/' + SUB_RAW.replace(/^\//, '');
  const ARGO_DOMAIN = PRESET_ARGO_DOMAIN || process.env.ARGO_DOMAIN || '';
  const ARGO_AUTH   = PRESET_ARGO_AUTH   || process.env.ARGO_AUTH   || '';

  // 隧道端口：固定隧道用预设或默认8001，临时隧道随机
  const ARGO_PORT = (ARGO_DOMAIN && ARGO_AUTH)
    ? parseInt(PRESET_ARGO_PORT || process.env.ARGO_PORT || '8001')
    : await getFreePort();

  const COUNTRY = await httpGet('https://ipinfo.io/country') ||
                  await httpGet('https://ifconfig.co/country-iso') ||
                  '';

  let NAME = PRESET_NAME || process.env.NAME || '';
  if (!NAME) {
    let ASN_ORG = await httpGet('https://ipinfo.io/org') ||
                  await httpGet('https://ifconfig.co/org') ||
                  '';
    ASN_ORG = ASN_ORG
      .replace(/^AS\d+\s+/, '')
      .replace(/,?\s*Inc\.?$/, '')
      .replace(/,?\s*LLC\.?/g, '')
      .replace(/,?\s*Ltd\.?/g, '')
      .replace(/,?\s*Corp\.?/g, '')
      .trim()
      .substring(0, 20);
    NAME = COUNTRY && ASN_ORG ? `${COUNTRY}-${ASN_ORG}` :
           COUNTRY ? `${COUNTRY}-xray` : 'xray';
  }

  const config = {
    log: { loglevel: 'warning' },
    inbounds: [
      {
        port: V_VMESS_PORT,
        listen: '127.0.0.1',
        protocol: 'vmess',
        settings: { clients: [{ id: UUID, alterId: 0 }] },
        streamSettings: { network: 'ws', wsSettings: { path: WS_PATH_VMESS } }
      },
      {
        port: V_VLESS_PORT,
        listen: '127.0.0.1',
        protocol: 'vless',
        settings: { clients: [{ id: UUID, flow: '' }], decryption: 'none' },
        streamSettings: { network: 'ws', wsSettings: { path: WS_PATH_VLESS } }
      },
      {
        port: V_TROJAN_PORT,
        listen: '127.0.0.1',
        protocol: 'trojan',
        settings: { clients: [{ password: TROJAN_PASS }] },
        streamSettings: { network: 'ws', wsSettings: { path: WS_PATH_TROJAN } }
      }
    ],
    outbounds: [{ protocol: 'freedom', settings: {} }]
  };

  fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2));

  let xrayBin = '';
  const xrayPaths = ['xray', '/usr/local/bin/xray', '/usr/bin/xray'];
  for (const p of xrayPaths) {
    try { execSync(`which ${p} 2>/dev/null || test -x ${p}`); xrayBin = p; break; } catch {}
  }
  if (!xrayBin) xrayBin = await downloadXray();

  const xrayEnv = { ...process.env };
  delete xrayEnv.PORT;

  const xray = spawn(xrayBin, ['run', '-config', CONFIG_FILE], {
    stdio: 'inherit',
    env: xrayEnv
  });
  xray.on('exit', (code) => process.exit(code));

  const argoServer = http.createServer((req, res) => {
    res.writeHead(400);
    res.end('Bad Request');
  });

  argoServer.on('upgrade', (req, socket, head) => {
    const path = req.url.split('?')[0];
    let targetPort;

    if (path === WS_PATH_VMESS) {
      targetPort = V_VMESS_PORT;
    } else if (path === WS_PATH_VLESS) {
      targetPort = V_VLESS_PORT;
    } else if (path === WS_PATH_TROJAN) {
      targetPort = V_TROJAN_PORT;
    } else {
      socket.destroy();
      return;
    }

    const proxy = net.connect(targetPort, '127.0.0.1', () => {
      proxy.write(
        `${req.method} ${req.url} HTTP/${req.httpVersion}\r\n` +
        Object.entries(req.headers).map(([k, v]) => `${k}: ${v}`).join('\r\n') +
        '\r\n\r\n'
      );
      proxy.write(head);
      socket.pipe(proxy);
      proxy.pipe(socket);
    });
    proxy.on('error', () => socket.destroy());
    socket.on('error', () => proxy.destroy());
  });

  argoServer.listen(ARGO_PORT, '127.0.0.1', () => {
    console.log(`Argo 转发服务启动，端口 ${ARGO_PORT}`);
  });

  const INDEX_HTML = fs.existsSync('./index.html')
    ? fs.readFileSync('./index.html', 'utf8')
    : '<html><body><h1>Hello World</h1></body></html>';

  const server = http.createServer((req, res) => {
    const url = req.url.split('?')[0];
    if (url === SUB_PATH) {
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(global.SUB_CONTENT || '');
    } else {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(INDEX_HTML);
    }
  });

  server.listen(INBOUND_PORT, '0.0.0.0', () => {
    console.log(`HTTP 服务启动，端口 ${INBOUND_PORT}`);
  });

  const cfBin = await downloadCloudflared();
  const argoHost = await startArgoTunnel(cfBin, ARGO_PORT, ARGO_DOMAIN, ARGO_AUTH);
  const HOST = argoHost || 'your-domain.com';

  const VMESS_OBJ = {
    v: '2', ps: NAME, add: CF_PREFER_HOST, port: '443',
    id: UUID, aid: '0', scy: 'auto', net: 'ws', type: 'none',
    host: HOST, path: WS_PATH_VMESS, tls: 'tls', sni: HOST
  };
  const VMESS_LINK = 'vmess://' + Buffer.from(JSON.stringify(VMESS_OBJ)).toString('base64');

  const VLESS_LINK = `vless://${UUID}@${CF_PREFER_HOST}:443` +
    `?encryption=none&security=tls&sni=${HOST}&type=ws&host=${HOST}` +
    `&path=${encodeURIComponent(WS_PATH_VLESS)}#${encodeURIComponent(NAME)}`;

  const TROJAN_LINK = `trojan://${TROJAN_PASS}@${CF_PREFER_HOST}:443` +
    `?security=tls&sni=${HOST}&type=ws&host=${HOST}` +
    `&path=${encodeURIComponent(WS_PATH_TROJAN)}#${encodeURIComponent(NAME)}`;

  const ALL_LINKS = [VMESS_LINK, VLESS_LINK, TROJAN_LINK].join('\n');
  const SUB_BASE64 = Buffer.from(ALL_LINKS).toString('base64');
  global.SUB_CONTENT = SUB_BASE64;

  const SUB_FILE = `${process.cwd()}/sub.txt`;
  fs.writeFileSync(SUB_FILE, SUB_BASE64);

  console.log('================= 订阅内容 =================');
  console.log(SUB_BASE64);
  console.log('============================================');
  console.log(`订阅地址: https://${HOST}${SUB_PATH}`);
  console.log(`节点文件: ${SUB_FILE}`);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
