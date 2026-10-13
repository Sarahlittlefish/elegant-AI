import { NextResponse } from 'next/server';
import { loadKaiPersona } from '@/lib/persona/loadPersona';
import { logChatTurn } from '@/lib/log/chatLog';

const ZHIPU_API_URL = 'https://open.bigmodel.cn/api/paas/v4/chat/completions';
// 默认 glm-4.6（关闭思考模式）。想换模型：设置环境变量 KAI_MODEL，比如 glm-4-plus、glm-5。
const MODEL_NAME = process.env.KAI_MODEL || 'glm-4.6';
const TEMPERATURE = Number(process.env.KAI_TEMPERATURE || 0.9);

/**
 * 发给模型的内容只有两部分：
 * 1. system：kai_persona_v2.md 原文（一个字都不改，不加任何别的提示词）
 * 2. 网页上的聊天记录，按顺序原样带上
 */
// 取出最后一条回复之后她发的消息（只用于写聊天记录）
function latestUserMessages(messages: unknown): string[] {
  const list = Array.isArray(messages) ? messages : [];
  const out: string[] = [];
  for (let i = list.length - 1; i >= 0; i--) {
    const m = list[i] || {};
    if (m.sender === 'user' || m.role === 'user') out.unshift(String(m.content ?? ''));
    else break;
  }
  return out;
}

export async function POST(req: Request) {
  let logBase: { user: string[]; model: string; historyLength: number } | null = null;
  try {
    const { messages, clientApiKey } = await req.json();
    logBase = {
      user: latestUserMessages(messages),
      model: MODEL_NAME,
      historyLength: Array.isArray(messages) ? messages.length : 0,
    };
    const apiKey = clientApiKey || process.env.ZHIPU_API_KEY || process.env.GLM_API_KEY;
    if (!apiKey) {
      return NextResponse.json({ error: '未检测到智谱 API Key。' }, { status: 400 });
    }

    const persona = loadKaiPersona();

    // 合并连续同一方的消息（比如开头两条剪贴板，或对方连发两条），保证 user / assistant 交替
    const chatTurns: { role: 'user' | 'assistant'; content: string }[] = [];
    for (const m of Array.isArray(messages) ? messages : []) {
      const role = m.sender === 'user' || m.role === 'user' ? 'user' : 'assistant';
      const content = String(m.content ?? '');
      const last = chatTurns[chatTurns.length - 1];
      if (last && last.role === role) {
        last.content += '\n\n' + content;
      } else {
        chatTurns.push({ role, content });
      }
    }

    const body: Record<string, unknown> = {
      model: MODEL_NAME,
      messages: [{ role: 'system', content: persona }, ...chatTurns],
      temperature: TEMPERATURE,
    };
    // glm-4.5 及以后的模型默认会先"思考"，聊天不需要，关掉更快也更像真人
    if (/^glm-(4\.[5-9]|[5-9])/.test(MODEL_NAME)) {
      body.thinking = { type: 'disabled' };
    }

    const response = await fetch(ZHIPU_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify(body),
    });
    if (!response.ok) {
      const errText = await response.text();
      await logChatTurn({ ...logBase, error: `模型接口异常 ${response.status}: ${errText.slice(0, 300)}` });
      return NextResponse.json({ error: `模型接口异常: ${errText}` }, { status: 500 });
    }
    const data = await response.json();
    let reply: string = data.choices?.[0]?.message?.content || '...';
    // 万一模型把思考过程写进回复里，去掉
    reply = reply.replace(/[\s\S]*<\/think>/, '').trim() || '...';

    await logChatTurn({ ...logBase, reply });

    return NextResponse.json({ reply });
  } catch (error: any) {
    if (logBase) await logChatTurn({ ...logBase, error: String(error?.message || '模型连接失败') });
    return NextResponse.json({ error: error.message || '模型连接失败' }, { status: 500 });
  }
}
