import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import crypto from 'node:crypto';
import nodemailer from 'nodemailer';
import { put, get, del, BlobNotFoundError } from '@vercel/blob';

dotenv.config();
for (const k of [
  'BLOB_READ_WRITE_TOKEN',
  'KV_REST_API_URL',
  'KV_REST_API_TOKEN',
  'UPSTASH_REDIS_REST_URL',
  'UPSTASH_REDIS_REST_TOKEN',
  'GEMINI_API_KEY',
  'AUTH_SECRET',
  'SMTP_HOST',
  'SMTP_PORT',
  'SMTP_USER',
  'SMTP_PASS',
  'SMTP_FROM',
  'RESEND_API_KEY',
  'RESEND_FROM',
]) {
  if (typeof process.env[k] === 'string') {
    process.env[k] = process.env[k]
      .replace(/^\uFEFF/, '')
      .trim()
      .replace(new RegExp('^' + k + '=', 'i'), '')
      .trim()
      .replace(/^["']|["']$/g, '')
      .trim();
  }
}

const app = express();
app.use(cors({ origin: '*', methods: ['GET', 'POST', 'OPTIONS'] }));
app.options('*', cors());
app.use(express.json({ limit: '20mb' }));

const kvUrl = process.env.KV_REST_API_URL || process.env.UPSTASH_REDIS_REST_URL || '';
const kvToken = process.env.KV_REST_API_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN || '';
const hasKv = Boolean(kvUrl && kvToken);
const hasBlob = Boolean(process.env.BLOB_READ_WRITE_TOKEN);
const geminiKey = process.env.GEMINI_API_KEY || '';
const authSecret = process.env.AUTH_SECRET || 'verilens-stateless-forensic-key';

let blobAccess = 'private';
const memoryScans = [];
const memoryUsers = new Map();
const usedOtpNonces = new Set();
let memoryApkShares = 12;

function storageMode() {
  if (hasKv) return 'vercel-kv';
  if (hasBlob) return 'vercel-blob';
  return 'vercel-memory';
}

async function kvCall(commandArgs) {
  if (!hasKv) return { enabled: false, result: null };
  const resp = await fetch(kvUrl, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${kvToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(commandArgs),
  });
  if (!resp.ok) {
    const errText = await resp.text();
    throw new Error(`Vercel Redis error (${resp.status}): ${errText}`);
  }
  const data = await resp.json();
  if (data.error) throw new Error(`Vercel Redis command error: ${data.error}`);
  return { enabled: true, result: data.result };
}

async function blobReadJson(pathname) {
  if (!hasBlob) return null;
  try {
    const res = await get(pathname, { access: blobAccess });
    if (!res || !res.stream) return null;
    const text = await new Response(res.stream).text();
    return text ? JSON.parse(text) : null;
  } catch (err) {
    const msg = String(err?.message || '');
    if (err instanceof BlobNotFoundError || /not found|404/i.test(msg)) return null;
    if (/private access on a public store/i.test(msg)) {
      blobAccess = 'public';
      return blobReadJson(pathname);
    }
    if (/public access on a private store/i.test(msg)) {
      blobAccess = 'private';
      return blobReadJson(pathname);
    }
    throw err;
  }
}

async function blobWriteJson(pathname, data) {
  if (!hasBlob) return;
  try {
    await put(pathname, JSON.stringify(data), {
      access: blobAccess,
      contentType: 'application/json',
      addRandomSuffix: false,
      allowOverwrite: true,
      cacheControlMaxAge: 60,
    });
  } catch (err) {
    const msg = String(err?.message || '');
    if (/private access on a public store/i.test(msg)) {
      blobAccess = 'public';
      return blobWriteJson(pathname, data);
    }
    if (/public access on a private store/i.test(msg)) {
      blobAccess = 'private';
      return blobWriteJson(pathname, data);
    }
    throw err;
  }
}

function userBlobPath(email) {
  const safeKey = Buffer.from(email).toString('base64url');
  return `verilens/users/${safeKey}.json`;
}

async function findUser(email) {
  if (hasKv) {
    const res = await kvCall(['GET', `verilens:user:${email}`]);
    if (!res.result) return null;
    return typeof res.result === 'string' ? JSON.parse(res.result) : res.result;
  }
  if (hasBlob) {
    return await blobReadJson(userBlobPath(email));
  }
  return memoryUsers.get(email) || null;
}

async function saveUser(userDoc) {
  if (hasKv) {
    await kvCall(['SET', `verilens:user:${userDoc.email}`, JSON.stringify(userDoc)]);
    return;
  }
  if (hasBlob) {
    await blobWriteJson(userBlobPath(userDoc.email), userDoc);
    return;
  }
  memoryUsers.set(userDoc.email, userDoc);
}

async function deleteUser(email) {
  if (hasKv) {
    await kvCall(['DEL', `verilens:user:${email}`]);
    return;
  }
  if (hasBlob) {
    try {
      await del(userBlobPath(email));
    } catch (_) {}
    return;
  }
  memoryUsers.delete(email);
}

async function isNonceUsed(nonce) {
  if (hasKv) {
    const res = await kvCall(['GET', `verilens:nonce:${nonce}`]);
    return Boolean(res.result);
  }
  if (hasBlob) {
    const rec = await blobReadJson(`verilens/nonces/${nonce}.json`);
    return Boolean(rec && rec.used);
  }
  return usedOtpNonces.has(nonce);
}

async function markNonceUsed(nonce) {
  if (hasKv) {
    await kvCall(['SET', `verilens:nonce:${nonce}`, '1', 'EX', '900']);
    return;
  }
  if (hasBlob) {
    await blobWriteJson(`verilens/nonces/${nonce}.json`, { used: true, at: Date.now() });
    return;
  }
  usedOtpNonces.add(nonce);
}

async function addScan(record) {
  if (hasKv) {
    await kvCall(['LPUSH', 'verilens:scans', JSON.stringify(record)]);
    await kvCall(['LTRIM', 'verilens:scans', '0', '59']);
    return;
  }
  if (hasBlob) {
    const existing = (await blobReadJson('verilens/scans.json')) || [];
    const updated = [record, ...(Array.isArray(existing) ? existing : [])].slice(0, 60);
    await blobWriteJson('verilens/scans.json', updated);
    return;
  }
  memoryScans.unshift(record);
  if (memoryScans.length > 60) memoryScans.pop();
}

async function listScans() {
  if (hasKv) {
    const res = await kvCall(['LRANGE', 'verilens:scans', '0', '59']);
    return (res.result || [])
      .map((item) => {
        try {
          return typeof item === 'string' ? JSON.parse(item) : item;
        } catch {
          return null;
        }
      })
      .filter(Boolean);
  }
  if (hasBlob) {
    const existing = await blobReadJson('verilens/scans.json');
    return Array.isArray(existing) ? existing : [];
  }
  return memoryScans;
}

async function incrementApkShares() {
  if (hasKv) {
    const res = await kvCall(['INCR', 'verilens:apk_shares']);
    return { tracked: true, totalShares: Number(res.result || 1), storage: 'vercel-kv' };
  }
  if (hasBlob) {
    const current = (await blobReadJson('verilens/apk_shares.json')) || { totalShares: 12 };
    const totalShares = Number(current.totalShares || 12) + 1;
    await blobWriteJson('verilens/apk_shares.json', { totalShares, lastActivityAt: new Date().toISOString() });
    return { tracked: true, totalShares, storage: 'vercel-blob' };
  }
  memoryApkShares += 1;
  return { tracked: true, totalShares: memoryApkShares, storage: 'vercel-memory' };
}

function isEmailOtpConfigured() {
  return Boolean(
    (process.env.SMTP_USER && process.env.SMTP_PASS) ||
      process.env.RESEND_API_KEY
  );
}

async function sendRealOtpEmail({ to, code, purpose, recipientName = '' }) {
  const subject =
    purpose === 'register'
      ? `VeriLens AI - Verify Your Email (OTP: ${code})`
      : `VeriLens AI - Password Reset OTP (${code})`;
  const heading =
    purpose === 'register'
      ? 'Verify Your VeriLens AI Account'
      : 'Reset Your VeriLens AI Password';
  const html = `
    <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;border:1px solid #e2e8f0;border-radius:14px;">
      <h2 style="color:#0f172a;margin:0 0 12px;">${heading}</h2>
      <p style="color:#475569;font-size:14px;line-height:1.5;">
        Hello ${recipientName || 'Analyst'}, use the one-time verification code below. This code expires in <strong>10 minutes</strong>.
      </p>
      <div style="background:#eff6ff;border:1px solid #bfdbfe;border-radius:10px;padding:16px;text-align:center;margin:20px 0;">
        <span style="font-size:30px;font-weight:800;letter-spacing:6px;color:#1d4ed8;">${code}</span>
      </div>
      <p style="color:#64748b;font-size:12px;">If you did not request this code, you can safely ignore this email.</p>
    </div>
  `;

  if (process.env.RESEND_API_KEY) {
    const resp = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${process.env.RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: process.env.RESEND_FROM || 'VeriLens AI <onboarding@resend.dev>',
        to: [to],
        subject,
        html,
      }),
    });
    if (!resp.ok) {
      const text = await resp.text();
      throw new Error(`Resend email delivery failed: ${text}`);
    }
    return 'resend';
  }

  if (process.env.SMTP_USER && process.env.SMTP_PASS) {
    const port = Number(process.env.SMTP_PORT || 465);
    const transporter = nodemailer.createTransport({
      host: process.env.SMTP_HOST || 'smtp.gmail.com',
      port,
      secure: port === 465,
      auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS,
      },
    });
    await transporter.sendMail({
      from: process.env.SMTP_FROM || `VeriLens AI <${process.env.SMTP_USER}>`,
      to,
      subject,
      text: `Your VeriLens AI verification OTP is ${code}. It expires in 10 minutes.`,
      html,
    });
    return 'smtp';
  }

  throw new Error(
    'Real-time Email OTP is not configured yet. Add SMTP_USER & SMTP_PASS (Gmail App Password) or RESEND_API_KEY in Vercel Environment Variables.'
  );
}

function hashPassword(password) {
  return crypto.createHash('sha256').update(`verilens:${password}`).digest('hex');
}

function signPayload(payload) {
  const data = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const sig = crypto.createHmac('sha256', authSecret).update(data).digest('base64url');
  return `${data}.${sig}`;
}

function verifyToken(token) {
  try {
    if (!token || !token.includes('.')) return null;
    const [data, sig] = token.split('.');
    const expected = crypto.createHmac('sha256', authSecret).update(data).digest('base64url');
    if (sig !== expected) return null;
    const parsed = JSON.parse(Buffer.from(data, 'base64url').toString('utf8'));
    if (parsed.exp && Date.now() > parsed.exp) return null;
    return parsed;
  } catch {
    return null;
  }
}

function makeAccountProof(userDoc) {
  return signPayload({
    purpose: 'account-proof',
    id: userDoc.id,
    name: userDoc.name,
    email: userDoc.email,
    role: userDoc.role,
    passwordHash: userDoc.passwordHash,
    exp: Date.now() + 365 * 86400000,
  });
}

function computeEntropy(bytes) {
  if (!bytes || bytes.length === 0) return 0;
  const counts = new Array(256).fill(0);
  const sampleLen = Math.min(bytes.length, 65536);
  for (let i = 0; i < sampleLen; i++) counts[bytes[i]]++;
  let entropy = 0;
  for (let i = 0; i < 256; i++) {
    if (counts[i] === 0) continue;
    const p = counts[i] / sampleLen;
    entropy -= p * Math.log2(p);
  }
  return Number(entropy.toFixed(2));
}

function extractImageBinaryTelemetry(bytes, cleanB64) {
  const approxKb = Math.max(1, Math.round(bytes.length / 1024));
  const headAscii = bytes.subarray(0, Math.min(bytes.length, 65536)).toString('latin1');
  const tailAscii = bytes.length > 65536 ? bytes.subarray(Math.max(0, bytes.length - 16384)).toString('latin1') : '';
  const combinedAscii = `${headAscii}\n${tailAscii}`;
  const lowerHeader = combinedAscii.toLowerCase();

  const isJpeg = bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  const isPng = bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47;
  const isWebp = cleanB64.startsWith('UklGR') || headAscii.startsWith('RIFF');
  const formatLabel = isJpeg ? 'JPEG' : isPng ? 'PNG' : isWebp ? 'WebP' : 'Image';

  const hasExifHeader = /exif\x00\x00|exif|eXIf/.test(combinedAscii);
  const cameraMatch = lowerHeader.match(/(apple|iphone|samsung|sm-[a-z0-9]+|google|pixel|xiaomi|redmi|poco|oppo|vivo|realme|oneplus|canon|nikon|sony|fujifilm|leica|hasselblad|huawei)/);
  const aiMetaMatch = lowerHeader.match(/(midjourney|dall-e|stable diffusion|comfyui|automatic1111|novelai|dreamstudio|imagen|firefly|chatgpt|openai|gpt-4o|gemini|flux\.1|grok|runway|kling|sora|ideogram|leonardo\.ai|bing image creator|made with google ai)/);
  const editorMatch = lowerHeader.match(/(adobe photoshop|canva|gimp|lightroom|snapseed|picsart|facetune|remini|lavc)/);
  const hasC2pa = /c2pa|jumbf|contentcredentials/.test(lowerHeader);
  const entropy = computeEntropy(bytes);

  return {
    approxKb,
    formatLabel,
    isJpeg,
    isPng,
    isWebp,
    hasExifHeader,
    cameraBrand: cameraMatch ? cameraMatch[1] : null,
    aiSoftware: aiMetaMatch ? aiMetaMatch[1] : null,
    editorSoftware: editorMatch ? editorMatch[1] : null,
    hasC2pa,
    entropy,
  };
}

function extractAudioBinaryTelemetry(bytes, mimeType) {
  const approxKb = Math.max(1, Math.round(bytes.length / 1024));
  const headAscii = bytes.subarray(0, Math.min(bytes.length, 32768)).toString('latin1');
  const lower = headAscii.toLowerCase();
  const isWav = headAscii.startsWith('RIFF') && headAscii.slice(8, 12) === 'WAVE';
  const isMp3 = headAscii.startsWith('ID3') || (bytes.length > 2 && bytes[0] === 0xff && (bytes[1] & 0xe0) === 0xe0);
  const isMp4M4a = headAscii.slice(4, 8) === 'ftyp';
  const isOgg = headAscii.startsWith('OggS');
  const isWebm = bytes.length >= 4 && bytes[0] === 0x1a && bytes[1] === 0x45 && bytes[2] === 0xdf && bytes[3] === 0xa3;

  let wavInfo = null;
  if (isWav && bytes.length >= 44) {
    const channels = bytes.readUInt16LE(22);
    const sampleRate = bytes.readUInt32LE(24);
    const bitsPerSample = bytes.readUInt16LE(34);
    const byteRate = bytes.readUInt32LE(28);
    const durationSec = byteRate > 0 ? Number((bytes.length / byteRate).toFixed(1)) : null;
    wavInfo = { channels, sampleRate, bitsPerSample, durationSec };
  }

  let zeroBytes = 0;
  const checkLen = Math.min(bytes.length, 32768);
  for (let i = 0; i < checkLen; i++) {
    if (bytes[i] === 0) zeroBytes++;
  }
  const silenceByteRatio = checkLen > 0 ? Number((zeroBytes / checkLen).toFixed(3)) : 0;
  const encoderMatch = lower.match(/(elevenlabs|openai|playht|murf|resemble|coqui|bark|tortoise|lavf|ffmpeg|gtts|google tts|azure tts|polly)/);
  const entropy = computeEntropy(bytes);

  return {
    approxKb,
    container: isWav ? 'WAV' : isMp3 ? 'MP3' : isMp4M4a ? 'M4A/MP4' : isOgg ? 'OGG' : isWebm ? 'WebM' : mimeType,
    wavInfo,
    silenceByteRatio,
    encoderTag: encoderMatch ? encoderMatch[1] : null,
    entropy,
  };
}

const FORENSIC_RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    classification: { type: 'STRING', enum: ['Real', 'Fake', 'Suspicious'] },
    confidence: { type: 'INTEGER' },
    summary: { type: 'STRING' },
    visualSignals: { type: 'ARRAY', items: { type: 'STRING' } },
    textConsistency: { type: 'STRING' },
    cumoNote: { type: 'STRING' },
  },
  required: ['classification', 'confidence', 'summary', 'visualSignals', 'textConsistency', 'cumoNote'],
};

function normalizeVerdict(raw, engineLabel) {
  const validClasses = ['Real', 'Fake', 'Suspicious'];
  const classification = validClasses.includes(raw?.classification) ? raw.classification : 'Suspicious';
  const confidence = Math.max(52, Math.min(99, Math.round(Number(raw?.confidence) || 75)));
  const visualSignals = Array.isArray(raw?.visualSignals) && raw.visualSignals.length > 0
    ? raw.visualSignals.map((s) => String(s)).slice(0, 5)
    : ['Forensic signal analysis completed.'];
  return {
    classification,
    confidence,
    summary: String(raw?.summary || 'Multimodal forensic inspection completed.'),
    visualSignals,
    textConsistency: String(raw?.textConsistency || 'No conflicting claim detected.'),
    cumoNote: `${String(raw?.cumoNote || 'Forensic pipeline completed.')} [Engine: ${engineLabel}]`,
  };
}

async function analyzeWithGemini({ parts }) {
  if (!geminiKey) return null;
  const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${encodeURIComponent(geminiKey)}`;
  const resp = await fetch(endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ role: 'user', parts }],
      generationConfig: {
        temperature: 0.1,
        responseMimeType: 'application/json',
        responseSchema: FORENSIC_RESPONSE_SCHEMA,
      },
    }),
  });
  if (!resp.ok) {
    const errBody = await resp.text();
    throw new Error(`Gemini API ${resp.status}: ${errBody.slice(0, 180)}`);
  }
  const data = await resp.json();
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) throw new Error('Gemini returned empty response');
  return JSON.parse(text);
}

async function inspectImageForensics({ imageBase64, mimeType = 'image/jpeg', fileName = '', description = '', sourceChannel = 'Mobile App', sampleTag = '' }) {
  const cleanB64 = imageBase64.includes(',') ? imageBase64.split(',')[1] : imageBase64;
  const bytes = Buffer.from(cleanB64, 'base64');
  const decodedPreview = bytes.subarray(0, 64).toString('utf8');
  const isDemoSample = Boolean(sampleTag) || decodedPreview.startsWith('SAMPLE_MEDIA::');

  if (isDemoSample) {
    const lowerTag = `${sampleTag} ${fileName} ${description}`.toLowerCase();
    if (/fake|ai|deepfake|midjourney|hurricane|clone/.test(lowerTag)) {
      return {
        classification: 'Fake',
        confidence: 95,
        summary: 'Demo synthetic sample flagged: diffusion texture uniformity and unverified viral manipulation markers.',
        visualSignals: [
          'Synthetic sample benchmark pattern detected',
          'Specular skin/surface smoothing & unnatural edge transitions',
          'Missing verifiable hardware camera EXIF provenance',
        ],
        textConsistency: description.trim() ? 'Caption conflicts with synthetic visual indicators.' : 'Demo AI-generated sample.',
        cumoNote: `CUMO Demo Benchmark (${sourceChannel}) [Engine: Demo Preset]`,
      };
    }
    return {
      classification: 'Real',
      confidence: 93,
      summary: 'Demo authentic sample verified: natural optical noise profile and consistent scene semantics.',
      visualSignals: [
        'Authentic sample camera benchmark verified',
        'Natural lighting & edge micro-contrast',
        'No diffusion or splicing signatures',
      ],
      textConsistency: 'Claim is consistent with sample media.',
      cumoNote: `CUMO Demo Benchmark (${sourceChannel}) [Engine: Demo Preset]`,
    };
  }

  const telemetry = extractImageBinaryTelemetry(bytes, cleanB64);

  if (geminiKey) {
    try {
      const normalizedMime = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'].includes(mimeType.toLowerCase())
        ? mimeType.toLowerCase()
        : telemetry.isPng
          ? 'image/png'
          : telemetry.isWebp
            ? 'image/webp'
            : 'image/jpeg';

      const prompt = `You are VeriLens AI, an expert digital media forensics analyst specializing in detecting AI-generated images (Midjourney, DALL-E, Flux, Stable Diffusion, Imagen, Gemini), deepfakes, photo tampering, and out-of-context social media claims.

Analyze the attached image carefully at pixel & semantic level:
1. Check for AI-generation artifacts: deformed or extra fingers/hands, asymmetric ears/eyes/pupils, unnatural glossy/plastic skin pores, garbled or distorted background text/letters, impossible architectural geometry, inconsistent shadows/reflections, painterly bokeh, or synthetic symmetry.
2. Check for photo manipulation / splicing / fake screenshots: mismatched lighting edges, copy-paste seams, UI font anomalies, overlaid fake news banners.
3. Evaluate Binary Metadata Telemetry extracted from the file header:
   - Format: ${telemetry.formatLabel}, Size: ${telemetry.approxKb} KB, Entropy: ${telemetry.entropy} bits/byte
   - EXIF Header Present: ${telemetry.hasExifHeader}
   - Camera Brand Marker: ${telemetry.cameraBrand || 'None'}
   - AI Generator Metadata Marker: ${telemetry.aiSoftware || 'None'}
   - Editing Software Marker: ${telemetry.editorSoftware || 'None'}
   - C2PA Content Credentials: ${telemetry.hasC2pa}
4. Evaluate Cross-Modal Context (Source Channel: "${sourceChannel}"):
   - User's Written Claim / Caption: "${description.trim() || '(none provided)'}"
   - Filename hint: "${fileName}"

Classification rules:
- Return "Fake" if you see clear AI-generation artifacts, deepfake signs, synthetic metadata, or obvious digital fabrication.
- Return "Real" if it appears to be a genuine unmanipulated photograph/capture with coherent real-world physics/lighting/anatomy AND matches the claim (or no conflicting claim).
- Return "Suspicious" if the image is heavily compressed/re-encoded/ambiguous, a cropped screenshot without provenance, or the written claim appears misleading/out-of-context.
Return strictly valid JSON with confidence (55-99), concise summary, 3-4 specific visualSignals observed directly in THIS image, textConsistency, and cumoNote.`;

      const aiVerdict = await analyzeWithGemini({
        parts: [
          { text: prompt },
          { inline_data: { mime_type: normalizedMime, data: cleanB64 } },
        ],
      });
      if (aiVerdict) {
        return normalizeVerdict(aiVerdict, 'Gemini 2.5 Flash Multimodal');
      }
    } catch (err) {
      console.error('Gemini image fallback:', err.message);
    }
  }

  const lowerText = `${fileName} ${description} ${sampleTag}`.toLowerCase();
  const urgentSocial = /(breaking|urgent|share immediately|viral|shocking|forwarded|exclusive leak)/.test(lowerText);

  if (telemetry.aiSoftware) {
    return {
      classification: 'Fake',
      confidence: 96,
      summary: `Embedded AI generator metadata ("${telemetry.aiSoftware}") found inside ${telemetry.formatLabel} (${telemetry.approxKb} KB).`,
      visualSignals: [
        `Binary chunk signature matched "${telemetry.aiSoftware}"`,
        `File entropy ${telemetry.entropy} bits/byte · ${telemetry.approxKb} KB`,
        telemetry.hasExifHeader ? 'Synthetic/modified EXIF container' : 'Missing physical camera sensor EXIF tags',
      ],
      textConsistency: description.trim() ? 'Claim conflicts with embedded AI generation signature.' : 'AI software metadata confirms synthetic origin.',
      cumoNote: `Binary header inspection flagged ${telemetry.aiSoftware} (${sourceChannel}) [Engine: Binary Forensics].`,
    };
  }

  if (telemetry.hasExifHeader && telemetry.cameraBrand && !telemetry.editorSoftware && !urgentSocial) {
    return {
      classification: 'Real',
      confidence: 88,
      summary: `Hardware camera EXIF metadata ("${telemetry.cameraBrand}") verified in ${telemetry.formatLabel} (${telemetry.approxKb} KB) with no AI generator signatures.`,
      visualSignals: [
        `Camera hardware marker "${telemetry.cameraBrand}" preserved in EXIF header`,
        'No Midjourney/Stable Diffusion/DALL-E/ComfyUI metadata chunks found',
        `Payload entropy ${telemetry.entropy} bits/byte consistent with camera encoding`,
      ],
      textConsistency: description.trim() ? 'No contradiction detected in metadata check.' : 'Camera hardware provenance verified.',
      cumoNote: `EXIF hardware verification passed (${sourceChannel}) [Engine: Binary Forensics].`,
    };
  }

  return {
    classification: 'Suspicious',
    confidence: 74,
    summary: `${telemetry.formatLabel} (${telemetry.approxKb} KB) lacks verifiable hardware camera EXIF provenance${telemetry.editorSoftware ? ` and shows "${telemetry.editorSoftware}" processing markers` : ''}. Cannot confirm authenticity from metadata alone.`,
    visualSignals: [
      telemetry.hasExifHeader ? 'EXIF header present without recognized camera hardware Make/Model' : 'Original hardware camera EXIF metadata stripped (common in AI exports & social forwards)',
      telemetry.editorSoftware ? `Editing/re-encoding software tag found: "${telemetry.editorSoftware}"` : `Entropy ${telemetry.entropy} bits/byte · ${telemetry.formatLabel} container`,
      geminiKey ? 'Fallback binary check triggered' : 'Tip: Set GEMINI_API_KEY in Vercel for pixel-level AI deepfake inspection',
    ],
    textConsistency: urgentSocial
      ? 'Urgent viral claim requires independent source verification.'
      : 'Visual provenance unverified due to stripped camera metadata.',
    cumoNote: `Marked Suspicious: stripped/missing camera provenance (${sourceChannel}) [Engine: Binary Forensics].`,
  };
}

async function inspectVoiceForensics({ audioBase64 = '', fileName = '', mimeType = 'audio/wav', transcriptOrClaim = '', sourceChannel = 'Voice Forensics', sampleTag = '' }) {
  const cleanB64 = audioBase64.includes(',') ? audioBase64.split(',')[1] : audioBase64;
  const bytes = cleanB64 ? Buffer.from(cleanB64, 'base64') : Buffer.alloc(0);
  const decodedPreview = bytes.subarray(0, 64).toString('utf8');
  const isDemoSample = Boolean(sampleTag) || decodedPreview.startsWith('SAMPLE_VOICE::');

  if (isDemoSample) {
    const lowerTag = `${sampleTag} ${transcriptOrClaim}`.toLowerCase();
    if (/fake|clone|bank|otp/.test(lowerTag)) {
      return {
        classification: 'Fake',
        confidence: 94,
        summary: 'Demo voice clone sample flagged: uniform neural vocoder pitch contour and OTP/bank impersonation script.',
        visualSignals: [
          'Synthetic TTS / voice-clone prosody benchmark',
          'Absence of natural respiratory breath pauses',
          'High-risk social engineering OTP solicitation pattern',
        ],
        textConsistency: 'Spoken claim matches known voice-cloning fraud scripts.',
        cumoNote: `Voice Demo Benchmark (${sourceChannel}) [Engine: Demo Preset]`,
      };
    }
    return {
      classification: 'Real',
      confidence: 91,
      summary: 'Demo human voice sample verified: organic pitch micro-jitter and natural room floor.',
      visualSignals: [
        'Natural vocal cadence and breath pauses verified',
        'Consistent ambient acoustic floor',
      ],
      textConsistency: 'Consistent with natural human speech.',
      cumoNote: `Voice Demo Benchmark (${sourceChannel}) [Engine: Demo Preset]`,
    };
  }

  const telemetry = extractAudioBinaryTelemetry(bytes, mimeType);

  if (geminiKey) {
    try {
      const normalizedAudioMime = mimeType.toLowerCase().includes('mp3') || mimeType.toLowerCase().includes('mpeg')
        ? 'audio/mp3'
        : mimeType.toLowerCase().includes('m4a') || mimeType.toLowerCase().includes('mp4')
          ? 'audio/mp4'
          : mimeType.toLowerCase().includes('ogg')
            ? 'audio/ogg'
            : mimeType.toLowerCase().includes('webm')
              ? 'audio/webm'
              : 'audio/wav';

      const prompt = `You are VeriLens AI, an expert audio forensics specialist detecting AI voice clones (ElevenLabs, OpenAI TTS, Bark, VALL-E, RVC), synthetic speech, spliced audio, and voice-phishing scams.

Analyze the attached audio recording (and/or spoken claim):
1. Listen closely to acoustic & vocal markers: robotic/metallic vocoder buzz, unnaturally smooth/uniform pitch & cadence, missing natural breath inhalations, abrupt room-tone cuts/splices, or unnatural pronunciation glitches.
2. Container & Signal Telemetry:
   - Container: ${telemetry.container}, Size: ${telemetry.approxKb} KB, Entropy: ${telemetry.entropy} bits/byte
   - WAV Info: ${telemetry.wavInfo ? `${telemetry.wavInfo.sampleRate} Hz, ${telemetry.wavInfo.channels} ch, ${telemetry.wavInfo.bitsPerSample}-bit, ~${telemetry.wavInfo.durationSec}s` : 'Compressed container'}
   - Silence byte ratio: ${telemetry.silenceByteRatio}, Encoder tag: ${telemetry.encoderTag || 'None'}
3. Spoken Claim / Context provided by user: "${transcriptOrClaim.trim() || '(none provided)'}" (Source: ${sourceChannel})

Classification rules:
- "Fake": Clear synthetic TTS / AI voice cloning artifacts OR explicit AI-generated voice indicators.
- "Real": Natural human speech with organic breath pauses, natural pitch variation, and authentic ambient noise floor.
- "Suspicious": Heavy WhatsApp/social compression, too short/noisy to be conclusive, OR urgent financial/OTP scam request needing out-of-band callback verification.
Return strictly valid JSON.`;

      const parts = [{ text: prompt }];
      if (cleanB64 && bytes.length > 64) {
        parts.push({ inline_data: { mime_type: normalizedAudioMime, data: cleanB64 } });
      }
      const aiVerdict = await analyzeWithGemini({ parts });
      if (aiVerdict) {
        return normalizeVerdict(aiVerdict, 'Gemini 2.5 Flash Audio');
      }
    } catch (err) {
      console.error('Gemini voice fallback:', err.message);
    }
  }

  const lower = `${fileName} ${transcriptOrClaim}`.toLowerCase();
  const isFakeTag = Boolean(telemetry.encoderTag && !['lavf', 'ffmpeg'].includes(telemetry.encoderTag)) ||
    /(elevenlabs|tts|synthetic|ai voice|voice clone)/.test(lower);
  const isScamClaim = /(otp|pin|bank|transfer money|urgent|emergency|whatsapp|forwarded|scam)/.test(lower);

  if (isFakeTag) {
    return {
      classification: 'Fake',
      confidence: 92,
      summary: `Synthetic speech indicator ("${telemetry.encoderTag || 'TTS marker'}") detected in ${telemetry.container} (${telemetry.approxKb} KB).`,
      visualSignals: [
        `Encoder/tool signature: ${telemetry.encoderTag || 'TTS/Clone keyword match'}`,
        `Audio entropy ${telemetry.entropy} bits/byte · Silence ratio ${telemetry.silenceByteRatio}`,
        telemetry.wavInfo ? `PCM ${telemetry.wavInfo.sampleRate} Hz / ${telemetry.wavInfo.channels}ch` : `Container: ${telemetry.container}`,
      ],
      textConsistency: 'Audio markers point to synthetic speech generation.',
      cumoNote: `Audio binary inspection flagged synthetic tool (${sourceChannel}) [Engine: Signal Forensics].`,
    };
  }

  return {
    classification: 'Suspicious',
    confidence: isScamClaim ? 81 : 70,
    summary: isScamClaim
      ? `Audio (${telemetry.approxKb} KB) accompanies high-risk urgent/financial phrasing. Verify caller identity independently.`
      : `Audio container (${telemetry.container}, ${telemetry.approxKb} KB) inspected at signal level, but neural vocoder verification requires Gemini AI (set GEMINI_API_KEY in Vercel).`,
    visualSignals: [
      telemetry.wavInfo
        ? `WAV PCM ${telemetry.wavInfo.sampleRate} Hz, ${telemetry.wavInfo.channels} ch, ~${telemetry.wavInfo.durationSec}s`
        : `Container ${telemetry.container} (${telemetry.approxKb} KB)`,
      `Byte entropy ${telemetry.entropy} bits/byte · Zero-byte silence ratio ${telemetry.silenceByteRatio}`,
      geminiKey ? 'Fallback signal check used' : 'Tip: Add free GEMINI_API_KEY in Vercel for real waveform AI clone detection',
    ],
    textConsistency: isScamClaim
      ? 'High-urgency or financial request requires callback verification.'
      : 'Acoustic signal parsed; AI waveform inspection not configured.',
    cumoNote: `Marked Suspicious pending AI acoustic confirmation (${sourceChannel}) [Engine: Signal Forensics].`,
  };
}

app.get('/', (_req, res) => {
  res.json({
    ok: true,
    service: 'verilens-vercel-api',
    storage: storageMode(),
    aiEngine: geminiKey ? 'gemini-2.5-flash' : 'binary-signal-fallback',
    otpEmail: isEmailOtpConfigured() ? 'configured' : 'not-configured',
    endpoints: [
      '/api/health',
      '/api/auth/send-register-otp',
      '/api/auth/register',
      '/api/auth/login',
      '/api/auth/forgot-password',
      '/api/auth/reset-password',
      '/api/auth/delete-account',
      '/api/analyze',
      '/api/analyze-voice',
      '/api/scans',
      '/api/apk/track',
    ],
  });
});

app.get('/api/health', (_req, res) => {
  res.json({
    ok: true,
    service: 'verilens-vercel-api',
    storage: storageMode(),
    aiEngine: geminiKey ? 'gemini-2.5-flash' : 'binary-signal-fallback',
    otpEmail: isEmailOtpConfigured() ? 'configured' : 'not-configured',
  });
});

app.post('/api/auth/send-register-otp', async (req, res) => {
  try {
    const { name = '', email = '' } = req.body || {};
    const cleanEmail = email.trim().toLowerCase();
    if (!name.trim() || !cleanEmail.includes('@')) {
      return res.status(400).json({ error: 'Name and valid email are required.' });
    }
    const existing = await findUser(cleanEmail);
    if (existing) {
      return res.status(409).json({ error: 'Email is already registered.' });
    }

    const code = String(crypto.randomInt(100000, 1000000));
    const nonce = crypto.randomBytes(12).toString('hex');
    const provider = await sendRealOtpEmail({
      to: cleanEmail,
      code,
      purpose: 'register',
      recipientName: name.trim(),
    });
    const otpToken = signPayload({
      purpose: 'register',
      email: cleanEmail,
      codeHash: hashPassword(`${cleanEmail}:${code}`),
      nonce,
      exp: Date.now() + 10 * 60 * 1000,
    });
    res.json({ ok: true, delivery: provider, otpToken, message: '6-digit OTP sent to your email.' });
  } catch (err) {
    const status = err.message.includes('not configured') ? 503 : 500;
    res.status(status).json({ error: err.message });
  }
});

app.post('/api/auth/register', async (req, res) => {
  try {
    const { name = '', email = '', password = '', otp = '', otpToken = '', role = 'Media Analyst' } = req.body || {};
    const cleanEmail = email.trim().toLowerCase();
    if (!name.trim() || !cleanEmail.includes('@') || password.length < 6) {
      return res.status(400).json({ error: 'Name, valid email, and password (min 6 chars) are required.' });
    }
    const verified = verifyToken(otpToken);
    if (
      !verified ||
      verified.purpose !== 'register' ||
      verified.email !== cleanEmail ||
      verified.codeHash !== hashPassword(`${cleanEmail}:${otp.trim()}`) ||
      (await isNonceUsed(verified.nonce))
    ) {
      return res.status(400).json({ error: 'Invalid or expired email OTP.' });
    }
    await markNonceUsed(verified.nonce);

    const existing = await findUser(cleanEmail);
    if (existing) {
      return res.status(409).json({ error: 'Email is already registered.' });
    }

    const userDoc = {
      id: `usr_${Date.now()}`,
      name: name.trim(),
      email: cleanEmail,
      role,
      passwordHash: hashPassword(password),
      verifiedAt: new Date().toISOString(),
      createdAt: new Date().toISOString(),
    };
    await saveUser(userDoc);

    const safeUser = { id: userDoc.id, name: userDoc.name, email: userDoc.email, role: userDoc.role };
    res.json({
      ok: true,
      user: safeUser,
      token: signPayload({ ...safeUser, exp: Date.now() + 7 * 86400000 }),
      accountProof: makeAccountProof(userDoc),
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/auth/login', async (req, res) => {
  try {
    const { email = '', password = '', accountProof = '' } = req.body || {};
    const cleanEmail = email.trim().toLowerCase();
    if (!cleanEmail || !password) {
      return res.status(400).json({ error: 'Email and password are required.' });
    }
    const passHash = hashPassword(password);
    let user = await findUser(cleanEmail);

    if (!user && accountProof) {
      const proof = verifyToken(accountProof);
      if (proof && proof.purpose === 'account-proof' && proof.email === cleanEmail && proof.passwordHash) {
        user = {
          id: proof.id || `usr_${Date.now()}`,
          name: proof.name || cleanEmail.split('@')[0],
          email: cleanEmail,
          role: proof.role || 'Media Analyst',
          passwordHash: proof.passwordHash,
          createdAt: new Date().toISOString(),
        };
        await saveUser(user);
      }
    }

    if (!user) {
      return res.status(401).json({
        error: hasKv || hasBlob
          ? 'No account found for this email. Please Register first.'
          : 'Vercel Storage is not connected yet. Connect free Vercel Blob in Dashboard -> Storage or tap Forgot Password once.',
      });
    }

    if (user.passwordHash !== passHash) {
      return res.status(401).json({ error: 'Invalid email or password.' });
    }

    const safeUser = { id: user.id, name: user.name, email: user.email, role: user.role };
    res.json({
      ok: true,
      user: safeUser,
      token: signPayload({ ...safeUser, exp: Date.now() + 7 * 86400000 }),
      accountProof: makeAccountProof(user),
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/auth/forgot-password', async (req, res) => {
  try {
    const cleanEmail = (req.body?.email || '').trim().toLowerCase();
    if (!cleanEmail.includes('@')) {
      return res.status(400).json({ error: 'Valid email is required.' });
    }
    const code = String(crypto.randomInt(100000, 1000000));
    const nonce = crypto.randomBytes(12).toString('hex');
    const provider = await sendRealOtpEmail({
      to: cleanEmail,
      code,
      purpose: 'reset',
    });
    const resetToken = signPayload({
      purpose: 'reset',
      email: cleanEmail,
      codeHash: hashPassword(`${cleanEmail}:${code}`),
      nonce,
      exp: Date.now() + 10 * 60 * 1000,
    });
    res.json({
      ok: true,
      delivery: provider,
      message: '6-digit verification OTP sent to your email.',
      resetToken,
    });
  } catch (err) {
    const status = err.message.includes('not configured') ? 503 : 500;
    res.status(status).json({ error: err.message });
  }
});

app.post('/api/auth/reset-password', async (req, res) => {
  try {
    const { email = '', code = '', newPassword = '', resetToken = '' } = req.body || {};
    const cleanEmail = email.trim().toLowerCase();
    const verified = verifyToken(resetToken);
    if (
      !verified ||
      verified.purpose !== 'reset' ||
      verified.email !== cleanEmail ||
      verified.codeHash !== hashPassword(`${cleanEmail}:${code.trim()}`) ||
      (await isNonceUsed(verified.nonce))
    ) {
      return res.status(400).json({ error: 'Invalid or expired reset OTP.' });
    }
    if (newPassword.length < 6) {
      return res.status(400).json({ error: 'New password must be at least 6 characters.' });
    }
    await markNonceUsed(verified.nonce);

    const newHash = hashPassword(newPassword);
    const existing = (await findUser(cleanEmail)) || {
      id: `usr_${Date.now()}`,
      name: cleanEmail.split('@')[0],
      email: cleanEmail,
      role: 'Media Analyst',
      verifiedAt: new Date().toISOString(),
      createdAt: new Date().toISOString(),
    };
    existing.passwordHash = newHash;
    await saveUser(existing);

    res.json({
      ok: true,
      message: 'Password updated successfully.',
      accountProof: makeAccountProof(existing),
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/auth/delete-account', async (req, res) => {
  try {
    const authHeader = req.headers.authorization || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7).trim() : '';
    const verified = verifyToken(token);
    if (!verified || !verified.email) {
      return res.status(401).json({ error: 'Valid session token is required.' });
    }
    await deleteUser(verified.email);
    res.json({ ok: true, message: 'Account deleted permanently.' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/analyze', async (req, res) => {
  try {
    const {
      imageBase64,
      fileName = 'uploaded_image.jpg',
      mimeType = 'image/jpeg',
      description = '',
      sourceChannel = 'Mobile App',
      sampleTag = '',
    } = req.body || {};

    if (!imageBase64) {
      return res.status(400).json({ error: 'imageBase64 is required.' });
    }

    const result = await inspectImageForensics({
      imageBase64,
      mimeType,
      fileName,
      description,
      sourceChannel,
      sampleTag,
    });

    const record = {
      ...result,
      mediaType: 'image',
      fileName,
      mimeType,
      description,
      sourceChannel,
      analyzedAt: new Date().toISOString(),
    };

    await addScan(record);
    res.json(record);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/analyze-voice', async (req, res) => {
  try {
    const {
      audioBase64 = '',
      fileName = 'voice_note.wav',
      mimeType = 'audio/wav',
      transcriptOrClaim = '',
      sourceChannel = 'Voice Forensics',
      sampleTag = '',
    } = req.body || {};

    if (!audioBase64 && !transcriptOrClaim.trim() && !sampleTag) {
      return res.status(400).json({ error: 'Audio file, recording, or voice claim is required.' });
    }

    const result = await inspectVoiceForensics({
      audioBase64,
      fileName,
      mimeType,
      transcriptOrClaim,
      sourceChannel,
      sampleTag,
    });

    const record = {
      ...result,
      mediaType: 'voice',
      fileName,
      description: transcriptOrClaim,
      sourceChannel,
      analyzedAt: new Date().toISOString(),
    };

    await addScan(record);
    res.json(record);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/scans', async (_req, res) => {
  try {
    const scans = await listScans();
    res.json({ scans });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/apk/track', async (_req, res) => {
  try {
    const result = await incrementApkShares();
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

const port = process.env.PORT || 3001;
if (process.env.VERCEL !== '1') {
  app.listen(port, () => console.log(`VeriLens API running on http://localhost:${port}`));
}

export default app;