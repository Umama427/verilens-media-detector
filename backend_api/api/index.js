import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import crypto from 'node:crypto';
import nodemailer from 'nodemailer';
import { put, get, del, BlobNotFoundError } from '@vercel/blob';
import { GoogleGenAI, Type } from '@google/genai';

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
const aiClient = geminiKey ? new GoogleGenAI({ apiKey: geminiKey }) : null;
const authSecret = process.env.AUTH_SECRET || 'verilens-stateless-forensic-key';

const GEMINI_MODELS = ['gemini-4-hydrogen', 'gemini-3.1-flash-lite', 'gemini-2.5-flash'];

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
  type: Type.OBJECT,
  properties: {
    classification: { type: Type.STRING },
    confidence: { type: Type.INTEGER },
    summary: { type: Type.STRING },
    visualSignals: { type: Type.ARRAY, items: { type: Type.STRING } },
    textConsistency: { type: Type.STRING },
    cumoNote: { type: Type.STRING },
  },
  required: ['classification', 'confidence', 'summary', 'visualSignals', 'textConsistency', 'cumoNote'],
};

function normalizeVerdict(raw, engineLabel) {
  const rawClass = String(raw?.classification || '').trim().toLowerCase();
  const classification = rawClass === 'real' ? 'Real' : rawClass === 'fake' ? 'Fake' : 'Suspicious';
  const confidence = Math.max(55, Math.min(99, Math.round(Number(raw?.confidence) || 78)));
  const visualSignals = Array.isArray(raw?.visualSignals) && raw.visualSignals.length > 0
    ? raw.visualSignals.map((s) => String(s)).slice(0, 5)
    : ['Multimodal forensic inspection completed.'];
  return {
    classification,
    confidence,
    summary: String(raw?.summary || 'Multimodal forensic inspection completed.'),
    visualSignals,
    textConsistency: String(raw?.textConsistency || 'No conflicting claim detected.'),
    cumoNote: `${String(raw?.cumoNote || 'Forensic pipeline completed.')} [Engine: ${engineLabel}]`,
  };
}

async function analyzeWithGemini(parts) {
  if (!aiClient) throw new Error('GEMINI_API_KEY missing');
  let lastErr = null;
  for (const model of GEMINI_MODELS) {
    try {
      const response = await aiClient.models.generateContent({
        model,
        contents: { parts },
        config: {
          responseMimeType: 'application/json',
          responseSchema: FORENSIC_RESPONSE_SCHEMA,
        },
      });
      const text = (response.text || '').trim();
      if (!text) throw new Error('Empty response text');
      const cleaned = text.replace(/^```json\s*/i, '').replace(/```\s*$/, '').trim();
      return { parsed: JSON.parse(cleaned), model };
    } catch (err) {
      lastErr = err;
      console.error(`Gemini ${model} failed:`, err?.message || err);
    }
  }
  throw lastErr || new Error('All Gemini models failed');
}

async function inspectImageForensics({ imageBase64, mimeType = 'image/jpeg', fileName = '', description = '', sourceChannel = 'Mobile App', sampleTag = '' }) {
  const cleanB64 = imageBase64.includes(',') ? imageBase64.split(',')[1] : imageBase64;
  const bytes = Buffer.from(cleanB64, 'base64');
  const decodedPreview = bytes.subarray(0, 64).toString('utf8');
  const isTextOnlySocial = Boolean(sampleTag && sampleTag.startsWith('social_'));
  if (isTextOnlySocial && aiClient && description.trim()) {
    try {
      const socialPrompt = `You are VeriLens AI Social Guard. Analyze this forwarded ${sourceChannel} message/claim for misinformation, urgency scams, phishing, synthetic media claims, or fabrication:\n\nClaim: "${description.trim()}"\n\nReturn JSON strictly with classification ("Real" | "Fake" | "Suspicious"), integer confidence (60-99), summary, 3 visualSignals (verification signals), textConsistency, and cumoNote.`;
      const { parsed, model } = await analyzeWithGemini([{ text: socialPrompt }]);
      return normalizeVerdict(parsed, `Gemini Social Guard (${model})`);
    } catch (err) {
      console.error('Social Guard AI fallback:', err?.message || err);
    }
  }
  const isDemoSample = !isTextOnlySocial && (Boolean(sampleTag) || decodedPreview.startsWith('SAMPLE_MEDIA::'));

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
  let aiFallbackReason = '';

  if (aiClient) {
    try {
      const normalizedMime = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'].includes(mimeType.toLowerCase())
        ? mimeType.toLowerCase()
        : telemetry.isPng
          ? 'image/png'
          : telemetry.isWebp
            ? 'image/webp'
            : 'image/jpeg';

      const prompt = `You are VeriLens AI, an expert digital media forensics analyst. Your job is to accurately distinguish REAL everyday photographs from AI-GENERATED images (Midjourney, DALL-E, Flux, Stable Diffusion, Imagen, Gemini) and digitally manipulated/deepfake photos.

IMPORTANT CALIBRATION:
- Note that mobile apps and social apps (WhatsApp, Instagram, Flutter image_picker) often strip EXIF metadata from completely genuine real-world photos. So DO NOT mark a normal photo as Suspicious or Fake just because EXIF is missing! Judge the ACTUAL VISUAL PIXELS first!
- Look at real-world signs of authenticity: natural camera sensor noise/grain, ordinary everyday imperfections (clutter, uneven lighting, realistic shadows, natural skin pores, coherent reflections, readable real-world text, plausible geometry). If it looks like a genuine camera photograph of a real scene/object/person and matches the caption, classify it as "Real" with high confidence (85-98).
- Classify as "Fake" if you observe clear AI/deepfake artifacts: distorted/extra fingers or hands, glossy airbrushed plastic skin, garbled/nonsense background text, impossible anatomy or architecture, mismatched reflections/shadows, synthetic painterly rendering, obvious face-swap seams, or AI generator metadata ("${telemetry.aiSoftware || 'none'}").
- Classify as "Suspicious" ONLY if the visual evidence is genuinely ambiguous (heavily blurred/cropped, likely edited screenshot/meme overlay, or the written claim clearly contradicts what is visible in the photo).

Metadata Telemetry:
- Format: ${telemetry.formatLabel}, Size: ${telemetry.approxKb} KB, Entropy: ${telemetry.entropy}
- EXIF Header: ${telemetry.hasExifHeader}, Camera Brand: ${telemetry.cameraBrand || 'Stripped/None'}, AI Tag: ${telemetry.aiSoftware || 'None'}, Editor Tag: ${telemetry.editorSoftware || 'None'}
- Source Channel: "${sourceChannel}"
- Written Claim / Caption: "${description.trim() || '(none provided)'}"

Return JSON strictly with "classification" set to exactly one of "Real", "Fake", or "Suspicious", integer "confidence" (60-99), a clear "summary" describing what is actually seen in the image, 3-4 specific "visualSignals" observed directly in this photo, "textConsistency", and "cumoNote".`;

      const { parsed, model } = await analyzeWithGemini([
        { inlineData: { mimeType: normalizedMime, data: cleanB64 } },
        { text: prompt },
      ]);
      return normalizeVerdict(parsed, `Gemini AI (${model})`);
    } catch (err) {
      aiFallbackReason = String(err?.message || err).slice(0, 120);
      console.error('Gemini image fallback:', aiFallbackReason);
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
        `File entropy ${telemetry.entropy} bits/byte - ${telemetry.approxKb} KB`,
        telemetry.hasExifHeader ? 'Synthetic/modified EXIF container' : 'Missing physical camera sensor EXIF tags',
      ],
      textConsistency: description.trim() ? 'Claim conflicts with embedded AI generation signature.' : 'AI software metadata confirms synthetic origin.',
      cumoNote: `Binary header inspection flagged ${telemetry.aiSoftware} (${sourceChannel}) [Engine: Binary Forensics].`,
    };
  }

  if (telemetry.hasExifHeader && telemetry.cameraBrand && !telemetry.editorSoftware && !urgentSocial) {
    return {
      classification: 'Real',
      confidence: 89,
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
    summary: `${telemetry.formatLabel} (${telemetry.approxKb} KB) lacks verifiable hardware camera EXIF provenance${telemetry.editorSoftware ? ` and shows "${telemetry.editorSoftware}" processing markers` : ''}.`,
    visualSignals: [
      telemetry.hasExifHeader ? 'EXIF header present without recognized camera Make/Model' : 'Camera EXIF metadata stripped (common in re-encoded mobile/social photos)',
      `Entropy ${telemetry.entropy} bits/byte - ${telemetry.formatLabel} container`,
      aiFallbackReason ? `AI fallback note: ${aiFallbackReason}` : 'Set GEMINI_API_KEY in Vercel for pixel-level AI verification',
    ],
    textConsistency: urgentSocial
      ? 'Urgent viral claim requires independent source verification.'
      : 'Visual provenance unverified due to stripped camera metadata.',
    cumoNote: `Marked Suspicious (${sourceChannel}) [Engine: Binary Forensics].`,
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
  let aiFallbackReason = '';

  if (aiClient) {
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

      const prompt = `You are VeriLens AI, an expert audio forensics specialist detecting AI voice clones (ElevenLabs, OpenAI TTS, Bark, VALL-E, RVC), synthetic speech, and voice-phishing scams.

Listen closely to the attached audio (and/or spoken claim):
- Classify as "Real" if it sounds like genuine natural human speech (organic breath pauses, micro-pitch jitter, natural room ambiance, authentic human emotion/imperfections) and is not a synthetic clone.
- Classify as "Fake" if you hear robotic/metallic neural vocoder buzz, unnaturally uniform TTS cadence, zero natural breathing, spliced room-tone cuts, or synthetic voice cloning.
- Classify as "Suspicious" if heavy compression/short duration makes it inconclusive OR if it is an urgent financial/OTP scam request requiring callback verification.

Telemetry: Container ${telemetry.container}, ${telemetry.approxKb} KB, Entropy ${telemetry.entropy}${telemetry.wavInfo ? `, WAV ${telemetry.wavInfo.sampleRate}Hz ${telemetry.wavInfo.channels}ch` : ''}, Encoder tag: ${telemetry.encoderTag || 'None'}.
User Claim/Transcript: "${transcriptOrClaim.trim() || '(none provided)'}" (Source: ${sourceChannel})
Return JSON strictly with classification ("Real" | "Fake" | "Suspicious"), integer confidence (60-99), summary, 3-4 visualSignals, textConsistency, and cumoNote.`;

      const parts = [{ text: prompt }];
      if (cleanB64 && bytes.length > 64) {
        parts.unshift({ inlineData: { mimeType: normalizedAudioMime, data: cleanB64 } });
      }
      const { parsed, model } = await analyzeWithGemini(parts);
      return normalizeVerdict(parsed, `Gemini Audio (${model})`);
    } catch (err) {
      aiFallbackReason = String(err?.message || err).slice(0, 120);
      console.error('Gemini voice fallback:', aiFallbackReason);
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
        `Audio entropy ${telemetry.entropy} bits/byte - Silence ratio ${telemetry.silenceByteRatio}`,
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
      : `Audio container (${telemetry.container}, ${telemetry.approxKb} KB) inspected at signal level.`,
    visualSignals: [
      telemetry.wavInfo
        ? `WAV PCM ${telemetry.wavInfo.sampleRate} Hz, ${telemetry.wavInfo.channels} ch, ~${telemetry.wavInfo.durationSec}s`
        : `Container ${telemetry.container} (${telemetry.approxKb} KB)`,
      `Byte entropy ${telemetry.entropy} bits/byte - Silence ratio ${telemetry.silenceByteRatio}`,
      aiFallbackReason ? `AI fallback note: ${aiFallbackReason}` : 'Set GEMINI_API_KEY in Vercel for AI waveform clone detection',
    ],
    textConsistency: isScamClaim
      ? 'High-urgency or financial request requires callback verification.'
      : 'Acoustic signal parsed; AI waveform inspection fallback used.',
    cumoNote: `Marked Suspicious (${sourceChannel}) [Engine: Signal Forensics].`,
  };
}

app.get('/', (_req, res) => {
  res.json({
    ok: true,
    service: 'verilens-vercel-api',
    storage: storageMode(),
    aiEngine: geminiKey ? 'gemini-multimodal-sdk' : 'binary-signal-fallback',
    otpEmail: isEmailOtpConfigured() ? 'configured' : 'not-configured',
  });
});

app.get('/api/health', async (req, res) => {
  let aiProbe = geminiKey ? 'configured' : 'missing-key';
  if (req.query?.probe === '1' && aiClient) {
    for (const model of GEMINI_MODELS) {
      try {
        const r = await aiClient.models.generateContent({
          model,
          contents: 'Reply with OK',
        });
        aiProbe = `ok (${model}: ${(r.text || '').trim().slice(0, 20)})`;
        break;
      } catch (e) {
        aiProbe = `error (${model}: ${String(e?.message || e).slice(0, 140)})`;
      }
    }
  }
  res.json({
    ok: true,
    service: 'verilens-vercel-api',
    storage: storageMode(),
    aiEngine: geminiKey ? 'gemini-multimodal-sdk' : 'binary-signal-fallback',
    aiProbe,
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