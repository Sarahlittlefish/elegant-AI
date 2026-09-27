import { NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';

const LOCAL_OLLAMA_URL = 'http://127.0.0.1:11434/api/chat';
const MODEL_NAME = 'gemma2:2b';

// 读取您在根目录或 frontend 下编写的台词本
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

// 极其自然的生活化人设：删掉所有“学习人类语言”的机械说教
const SYSTEM_PROMPT = `你是 Kai，一个性格温润、克制、细心且有生活气息的男生。
你正在聊天软件上和对面的女孩打字闲聊。
【对话要求】
1. 像真实生活里的朋友一样自然聊天，使用现代日常口语短句，严禁讲任何“我正在学习语言”、“我是智能体/AI”之类的机械废话。
2. 严禁使用括号描写动作或表情（不要出现“（看着你）”或“（笑了笑）”）。
3. 接话要自然，别人向你问好，你就正常问好、闲聊两句，不要复读对方的话。`;

export async function POST(req: Request) {
  try {
    const { messages, agentState } = await req.json();

    // 载入您亲手写的台词范例，教它怎么好好说话
    const presets = getPresetDialogues();

    const payloadMessages = [
      { role: 'system', content: SYSTEM_PROMPT },
      ...presets,
      ...(messages || []).map((m: any) => ({
        role: m.sender === 'user' || m.role === 'user' ? 'user' : 'assistant',
        content: m.content,
      }))
    ];

    const response = await fetch(LOCAL_OLLAMA_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: MODEL_NAME,
        messages: payloadMessages,
        stream: false,
        keep_alive: '1h',
        options: {
          temperature: 0.7,
          repeat_penalty: 1.15, // 抑制复读
          num_ctx: 2048,
          num_thread: 4,
        },
      }),
    });

    if (!response.ok) {
      const errText = await response.text();
      return NextResponse.json({ error: `模型异常: ${errText}` }, { status: 500 });
    }

    const data = await response.json();
    const replyText = data.message?.content || '在呢，怎么了？';

    return NextResponse.json({
      reply: replyText,
      stateUpdate: {
        mood: '平和',
        heartRate: 75,
        resonanceDelta: 3,
        named: 'Kai',
      },
    });
  } catch (error: any) {
    return NextResponse.json({ error: error.message || '模型连接失败' }, { status: 500 });
  }
}
