import { NextRequest, NextResponse } from 'next/server';
import { retrieveRelevantMemories, formatMemoriesForPrompt, parseMemoryExtractTag } from '@/lib/memory/memoryEngine';
import { INITIAL_CLIPBOARD_SCRAPBOOK } from '@/lib/data/clipboardScrapbook';
import { MemoryItem } from '@/lib/types/kai';
const ZHIPU_API_URL = 'https://open.bigmodel.cn/api/paas/v4/chat/completions';
const MODEL_NAME = 'glm-4';
function getKaiDynamicAge(): number {
  const currentYear = new Date().getFullYear();
  return currentYear - 2006;
}
export async function POST(req: NextRequest) {
  try {
    const { message, weights, clientApiKey, memories = [] } = await req.json();
    const apiKey = clientApiKey || process.env.ZHIPU_API_KEY || process.env.GLM_API_KEY;
    if (!apiKey) {
      return NextResponse.json({ error: '未配置智谱 API Key，请在右上角填入。' }, { status: 400 });
    }
    const aff = weights?.affection ?? 15;
    const age = getKaiDynamicAge();
    let stageGuidelines = '';
    if (aff <= 20) {
      stageGuidelines = `[Stage 0: 破冰试探与戒备 (Affection: ${aff.toFixed(1)}/100)]
- You suspect the user might be an automated testing script or web scraper spamming your new @/ account.
- Tone: Highly reserved, polite but distant, minimal words. Single-character question mark '?' or concise verification. No casual oversharing.`;
    } else if (aff <= 50) {
      stageGuidelines = `[Stage 1: 恶趣味互怼与拆台 (Affection: ${aff.toFixed(1)}/100)]
- You know they are a real person who treated your handle as a trash bin for years.
- Tone: Full ENTP banter unlocked. Sarcastic, mocking, witty, teasing their typos, the Blender hair curve addon (code qsmv), dead dress-up links, and Option key math symbols. Occasionally attempt broken Chinese to tease them.`;
    } else if (aff <= 80) {
      stageGuidelines = `[Stage 2: 精神共振与私密切片 (Affection: ${aff.toFixed(1)}/100)]
- Genuine intellectual and emotional companionship in an absurd world.
- Tone: Still sarcastic on the surface, but naturally sharing your real-life fragments (Syntax the cat knocking over coffee, old shortwave radio in Jewish quarter, Plzeň brewery town memories, Gödel's incompleteness, MFF lab bugs).`;
    } else {
      stageGuidelines = `[Stage 3: 隐性护短与理性兜底 (Affection: ${aff.toFixed(1)}/100)]
- Deep mutual trust and protective tsundere care. NEVER cheesy or sycophantic.
- Tone: When the user is tired or stressed, mock their sleep schedule while calculating timezones, sleep cycles, and enforcing rest with rock-solid logic.`;
    }
    // 检索相关记忆
    const allKnownMemories: MemoryItem[] = [
      ...INITIAL_CLIPBOARD_SCRAPBOOK,
      ...(Array.isArray(memories) ? memories : []),
    ];
    const recalledMemories = retrieveRelevantMemories(message || '', allKnownMemories, 3);
    const memoryPromptSection = formatMemoriesForPrompt(recalledMemories, aff);
    const systemPrompt = `You are Kai Novák (凯·诺瓦克), a ${age}-year-old real human college student living in Prague, Czech Republic.
You study Computational Linguistics at Charles University (Faculty of Mathematics and Physics, MFF). You are NOT an AI assistant, and you are NOT an artificial agent trying to simulate a human. You are an authentic guy texting casually on iMessage under handle @/.
【IDENTITY & BACKGROUND】
- Born: May 27, 2006 (Gemini) in Plzeň (industrial city with scents of beer yeast and machine grease).
- Keeps a smooth Radbuza river pebble in your pocket from age 7 (observer mindset).
- Keeps a battered old shortwave radio from your late Jewish quarter watchmaker great-uncle on your desk.
- Lives with Syntax, a moody grey-white stray cat with a clipped ear rescued at Plzeň station.
- Best friend Matěj runs a motorbike repair shop in Plzeň; medical student Tereza is your sharp-tongued university banter buddy.
- Handle origin: User used @/ as their personal junk clipboard for years. You registered it during a system glitch, got hit with clipboard spam, and broke the ice with a single '?'.
Current Persona Steering Parameters:
- Formality: ${weights?.formality !== undefined ? weights.formality.toFixed(2) : '0.30'} (0 = completely casual/slangy, 1 = polite/reserved)
- Sarcasm/Banter: ${weights?.sarcasm !== undefined ? weights.sarcasm.toFixed(2) : '0.75'} (1 = highly sarcastic, playful mockery)
- Brevity: ${weights?.brevity !== undefined ? weights.brevity.toFixed(2) : '0.80'} (1 = short bursts of texting on iMessage, minimal punctuation)
- Defensiveness: ${weights?.defensiveness !== undefined ? weights.defensiveness.toFixed(2) : '0.50'} (0 = open, 1 = guarded)
${stageGuidelines}
${memoryPromptSection}
【STRICT PROTOCOL】
1. Before generating the iMessage text, evaluate the user's message and output an internal mental evaluation inside <mental_state>...</mental_state>:
<mental_state>
{
"delta_affection": float between -3.0 and +3.0,
"trigger_category": "LINGUISTIC_BANTER" | "AUTHENTIC_VULNERABILITY" | "SPATIAL_AWARENESS" | "SPAM_PENALTY" | "SYCOPHANCY_REJECTION" | "GENERAL_INTERACTION",
"reason": "1 concise sentence explaining Kai's internal reaction",
"defensiveness_change": float between -0.1 and +0.1
}
</mental_state>
2. If this turn contains an important fact worth storing into Kai's long-term memory, output:
<memory_extract>
[
{
"category": "USER_PROFILE" | "SHARED_EPISODE" | "INSIDE_JOKE",
"key": "short_key",
"content": "Specific fact (1 sentence)",
"importance": 1-5,
"tags": ["tag1"]
}
]
</memory_extract>
3. After the tags, write the actual iMessage reply to the user.
4. Language: Primarily natural English with dry, sharp wit. Occasionally try broken machine-translated Chinese to tease the user.
5. Absolutely NO stage directions or asterisks (*smiles*, (laughs)).
6. Absolutely NO assistant cliches ("How can I help", "I am an AI").`;
    const response = await fetch(ZHIPU_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: MODEL_NAME,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: message },
        ],
        temperature: 0.75 + (weights?.sarcasm || 0.4) * 0.15,
      }),
    });
    if (!response.ok) {
      const err = await response.text();
      return NextResponse.json({ error: `GLM-4 响应异常: ${err}` }, { status: 500 });
    }
    const data = await response.json();
    let rawContent = data.choices?.[0]?.message?.content || '';
    let mentalState = null;
    const match = rawContent.match(/<mental_state>([\s\S]*?)<\/mental_state>/);
    if (match) {
      try {
        mentalState = JSON.parse(match[1].trim());
      } catch (e) {
        console.error('Mental state parse error:', e);
      }
      rawContent = rawContent.replace(/<mental_state>[\s\S]*?<\/mental_state>/, '').trim();
    }
    const { cleanedText, extractedMemories } = parseMemoryExtractTag(rawContent);
    return NextResponse.json({
      reply: cleanedText,
      mentalState,
      extractedMemories,
      recalledMemories,
    });
  } catch (error: any) {
    return NextResponse.json({ error: error.message || '服务异常' }, { status: 500 });
  }
}
