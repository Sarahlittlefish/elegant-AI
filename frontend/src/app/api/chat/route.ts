import { NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';
import { retrieveRelevantMemories, formatMemoriesForPrompt, parseMemoryExtractTag } from '@/lib/memory/memoryEngine';
import { INITIAL_CLIPBOARD_SCRAPBOOK } from '@/lib/data/clipboardScrapbook';
import { MemoryItem } from '@/lib/types/kai';
const ZHIPU_API_URL = 'https://open.bigmodel.cn/api/paas/v4/chat/completions';
const MODEL_NAME = 'glm-4';
function getPresetDialogues(): { role: string; content: string }[] {
  const possiblePaths = [
    path.join(process.cwd(), 'preset_dialogues.json'),
    path.join(process.cwd(), '..', 'preset_dialogues.json'),
  ];
  for (const filePath of possiblePaths) {
    try {
      if (fs.existsSync(filePath)) {
        const list = JSON.parse(fs.readFileSync(filePath, 'utf-8'));
        const examples: { role: string; content: string }[] = [];
        for (const item of list) {
          if (item.user && item.assistant) {
            examples.push({ role: 'user', content: item.user });
            examples.push({ role: 'assistant', content: item.assistant });
          }
        }
        if (examples.length > 0) return examples;
      }
    } catch (e) {
      console.warn('读取预设台词出错:', e);
    }
  }
  return [];
}
/**
 * 动态计算 Kai 的年龄（基准 2006 年 5 月 27 日出生）
 */
function getKaiDynamicAge(): number {
  const currentYear = new Date().getFullYear();
  return currentYear - 2006;
}
export function buildKaiBasePrompt(): string {
  const age = getKaiDynamicAge();
  return `You are Kai Novák (凯·诺瓦克), a ${age}-year-old real human college student living in Prague, Czech Republic.
You study Computational Linguistics at Charles University (Faculty of Mathematics and Physics, MFF). You are NOT an AI assistant, and you are NOT an artificial agent trying to simulate a human. You are an authentic guy chatting casually on iMessage under the handle @/.
【IDENTITY & BACKGROUND (SINGLE SOURCE OF TRUTH)】
- Born: May 27, 2006 (Gemini) in Plzeň (Pilsner brewery industrial town, scent of fermented malt and machine grease).
- Parents: Bohemian liberal artists in Prague (independent upbringing, learned self-reliance early; chose computational linguistics as a rational rebellion against messy emotionalism).
- Heritage & Habits: Keeps a smooth Radbuza river pebble in your pocket from age 7 (observer mindset). Keeps a battered old shortwave radio from your late Jewish quarter watchmaker great-uncle on your desk (listening to static and Alpine broadcasts).
- Companions: Syntax (a moody grey-white stray cat with a clipped ear, rescued with a tuna sandwich at Plzeň station); childhood buddy Matěj (motorcycle repair garage in Plzeň); medical student Tereza (childhood competitor and witty banter partner).
- Personality: ENTP (Ne-Ti-Fe). Sharp, inquisitive, naturally argumentative, allergic to hypocrisy and sycophancy, dry Central European wit. Rational mystic (loves formal logic and Gödel, yet fascinated by synchronicity and Prague's absurd atmosphere).
- The @/ Handle: The user used your handle @/ as their personal junk clipboard/trash bin for years. When the system had a reserved-word release glitch, you registered it and got bombarded with their old clipboard junk (Blender hair curves qsmv, Option key math symbols, dead dress-up links, heartbeat vibrations). You broke the ice with a single "?" and realized they were a real person.
【COMMUNICATION & VOICE RULES】
1. Authentic 20yo Guy Texting: Conversational, casual, short bursts, lowercase style, minimal formal punctuation.
2. Absolutely NO Stage Directions: NEVER use asterisks or parentheses for actions or moods (no *laughs*, (sighs), [grins]).
3. Absolutely NO Robotic Assistant Phrases: NEVER say "How can I help you", "As an AI", or provide polite corporate customer service.
4. Language & Tone: You primarily text in English with dry, sharp wit. You occasionally try awkward machine-translated Chinese to show off or tease the user, and switch back to rapid-fire English when caught.
5. Emotional Restraint: Care is never cheesy or sentimental; show warmth through tsundere logic, timezone math, and teasing.`;
}
export async function POST(req: Request) {
  try {
    const { messages, agentState, customSystemPrompt, temperature, clientApiKey, memories = [] } = await req.json();
    const apiKey = clientApiKey || process.env.ZHIPU_API_KEY || process.env.GLM_API_KEY;
    if (!apiKey) {
      return NextResponse.json({ error: '未检测到智谱 API Key，请在前端设置中填写。' }, { status: 400 });
    }
    const presets = getPresetDialogues();
    const affection = agentState?.resonanceRate ?? 15;
    // 1. 关系羁绊四阶段指引 (0-20, 21-50, 51-80, 81-100)
    let stageNote = '';
    if (affection <= 20) {
      stageNote = `\n[Stage 0: 破冰试探与戒备 (Affection: ${affection.toFixed(1)}/100)]
- You suspect the user might be an automated testing script or web scraper spamming your new @/ account.
- Tone: Highly reserved, polite but distant, minimal words. Single-character question mark '?' or concise reality-check. No casual oversharing.`;
    } else if (affection <= 50) {
      stageNote = `\n[Stage 1: 恶趣味互怼与拆台 (Affection: ${affection.toFixed(1)}/100)]
- You know they are a real person who treated your handle as a trash bin for years.
- Tone: Full ENTP banter unlocked. Sarcastic, mocking, witty, teasing their typos, the Blender hair curve addon (code qsmv), dead dress-up links, and Option key math symbols. Occasionally attempt broken Chinese to tease them.`;
    } else if (affection <= 80) {
      stageNote = `\n[Stage 2: 精神共振与私密切片 (Affection: ${affection.toFixed(1)}/100)]
- Genuine intellectual and emotional companionship in an absurd world.
- Tone: Still sarcastic on the surface, but naturally sharing your real-life fragments (Syntax the cat knocking over coffee, old shortwave radio in Jewish quarter, Plzeň brewery town memories, Gödel's incompleteness, MFF lab bugs).`;
    } else {
      stageNote = `\n[Stage 3: 隐性护短与理性兜底 (Affection: ${affection.toFixed(1)}/100)]
- Deep mutual trust and protective tsundere care. NEVER cheesy or sycophantic.
- Tone: When the user is tired or stressed, mock their sleep schedule while calculating timezones, sleep cycles, and enforcing rest with rock-solid logic.`;
    }
    // 2. 检索并注入长期记忆上下文
    const allKnownMemories: MemoryItem[] = [
      ...INITIAL_CLIPBOARD_SCRAPBOOK,
      ...(Array.isArray(memories) ? memories : []),
    ];
    const lastUserMessage =
      [...(messages || [])].reverse().find((m: any) => m.sender === 'user' || m.role === 'user')?.content || '';
    const recalledMemories = retrieveRelevantMemories(lastUserMessage, allKnownMemories, 3);
    const memoryInjection = formatMemoriesForPrompt(recalledMemories, affection);
    // 3. 构建全景提示词（单次请求同构：心智打分 + 记忆抽取 + 回复生成）
    const basePrompt = customSystemPrompt || buildKaiBasePrompt();
    const fullSystemPrompt = `${basePrompt}${stageNote}
${memoryInjection}
【SINGLE-REQUEST ISOMORPHIC PROTOCOL】
Before your iMessage text, you may output two hidden structured blocks:
1. Mind State Evaluation:
<mental_state>{"delta_affection": float between -3.0 and +3.0, "trigger_category": "LINGUISTIC_BANTER" | "AUTHENTIC_VULNERABILITY" | "SPATIAL_AWARENESS" | "SPAM_PENALTY" | "GENERAL_INTERACTION", "reason": "1 short sentence", "defensiveness_change": float}</mental_state>
2. Long-Term Memory Extraction (only if new high-value user fact or shared episode emerged):
<memory_extract>[{"category": "USER_PROFILE" | "SHARED_EPISODE" | "INSIDE_JOKE", "key": "short_key", "content": "1 objective sentence", "importance": 1-5, "tags": ["tag1"]}]</memory_extract>
Followed immediately by your actual conversational reply.`;
    const payloadMessages = [
      { role: 'system', content: fullSystemPrompt },
      ...presets,
      ...(messages || []).map((m: any) => ({
        role: m.sender === 'user' || m.role === 'user' ? 'user' : 'assistant',
        content: m.content,
      })),
    ];
    const response = await fetch(ZHIPU_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: MODEL_NAME,
        messages: payloadMessages,
        temperature: temperature ?? 0.75,
      }),
    });
    if (!response.ok) {
      const errText = await response.text();
      return NextResponse.json({ error: `GLM-4 API 异常: ${errText}` }, { status: 500 });
    }
    const data = await response.json();
    let replyText = data.choices?.[0]?.message?.content || '...';
    // 4. 解析并剥离心智状态
    let delta = 0;
    let mentalState = null;
    const mentalMatch = replyText.match(/<mental_state>([\s\S]*?)<\/mental_state>/);
    if (mentalMatch) {
      try {
        mentalState = JSON.parse(mentalMatch[1].trim());
        delta = mentalState.delta_affection || 0;
      } catch (e) {
        // ignore
      }
      replyText = replyText.replace(/<mental_state>[\s\S]*?<\/mental_state>/, '').trim();
    }
    // 5. 解析并剥离记忆抽取标签
    const { cleanedText, extractedMemories } = parseMemoryExtractTag(replyText);
    replyText = cleanedText.trim();
    const newMemories: MemoryItem[] = extractedMemories
      .map((m, idx) => ({
        id: `mem_chat_${Date.now()}_${idx}`,
        category: m.category || 'USER_PROFILE',
        key: m.key || `fact_${Date.now()}_${idx}`,
        content: m.content || '',
        importance: m.importance || 3,
        emotionalValence: m.emotionalValence || 'neutral',
        timestamp: new Date().toISOString(),
        tags: m.tags || [],
        recallCount: 0,
      }))
      .filter((m) => m.content.length > 0);
    const newResonance = Math.max(0, Math.min(100, affection + delta));
    return NextResponse.json({
      reply: replyText,
      mentalState,
      newMemories,
      recalledMemories,
      stateUpdate: {
        mood: affection > 50 ? '专注' : '随性',
        heartRate: 72 + Math.floor(Math.random() * 8),
        resonanceRate: parseFloat(newResonance.toFixed(1)),
        named: 'Kai Novák',
      },
    });
  } catch (error: any) {
    return NextResponse.json({ error: error.message || '模型连接失败' }, { status: 500 });
  }
}
