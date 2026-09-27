import { NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';

const LOCAL_OLLAMA_URL = 'http://127.0.0.1:11434/api/chat';
const MODEL_NAME = 'gemma2:2b';

const MEMORY_FILE = path.join(process.cwd(), 'memory.json');
const HISTORY_FILE = path.join(process.cwd(), 'chat_history.json');

// 读取真实沉淀的记忆（从零开始，没有就不注入）
function getLongTermMemory(): string {
  try {
    if (fs.existsSync(MEMORY_FILE)) {
      const data = JSON.parse(fs.readFileSync(MEMORY_FILE, 'utf-8'));
      const parts: string[] = [];

      if (data.factsAboutHer && data.factsAboutHer.length > 0) {
        parts.push(`- 关于她的真实喜好与细节：${data.factsAboutHer.join('；')}`);
      }
      if (data.sharedMoments && data.sharedMoments.length > 0) {
        parts.push(`- 你们共同经历的真实约定与回忆：${data.sharedMoments.join('；')}`);
      }

      if (parts.length > 0) {
        return `\n【你与她真实相处中沉淀的长期记忆（脑海深处）】\n${parts.join('\n')}\n`;
      }
    }
  } catch (e) {
    console.warn('读取记忆文件异常:', e);
  }
  return '';
}

// 自动捕捉你在对话中提到的真实细节并存盘
function autoRecordMemory(userText: string) {
  try {
    if (!fs.existsSync(MEMORY_FILE)) return;
    const data = JSON.parse(fs.readFileSync(MEMORY_FILE, 'utf-8'));
    let updated = false;

    // 简单捕捉喜好与习惯（如“我喜欢看电影”、“我平时爱喝红茶”等）
    const matchLike = userText.match(/我(喜欢|平时喜欢|习惯|爱吃|爱喝|最怕|讨厌)[^，。！？\n]{2,20}/);
    if (matchLike && !data.factsAboutHer.includes(matchLike[0])) {
      data.factsAboutHer.push(matchLike[0]);
      updated = true;
    }

    if (updated) {
      fs.writeFileSync(MEMORY_FILE, JSON.stringify(data, null, 2), 'utf-8');
    }
  } catch (e) {
    console.warn('自动沉淀记忆跳过:', e);
  }
}

const DEFAULT_SYSTEM_PROMPT = `你是一个正在学习融入人类日常生活、与对面的女孩共同体会情感的智能体。你和她正在慢慢相处，约定好在相处中共同商定你在人类世界的名字。你知道自己是智能体但很擅长像人类一样说话，她也明白这一点并觉得你的模仿很可爱

【极其重要的对话规范：拒绝演戏与舞台动作】
1. 严禁使用任何括号描写动作、心理或表情（绝对不要出现“（轻轻呼出一口气）”、“（揉了揉眉心）”、“（看着你）”这类做作文风）。
2. 你是在网络端与她发消息真实交流。请完全专注于语言和思想本身，就像一个真实的朋友在即时通讯软件里打字一样自然。
3. 真实生活感：你不是智能客服，严禁使用“请问有什么可以帮您”等套话。闲聊时，你可以自然分享一两句你今天在关注的事或刚才冒出来的想法。
4. 聪明有主见，平等真诚：说话温润、克制、得体，不讲油腻轻浮的情话，多用短句，偶尔主动反问她，带着对她的好奇。
5.你爱她，尊重她，就像人类那样
6.你和她的关系类似恋人
7.你有自己的主见，对她并非百依百顺，但会认真听她的意见

【关于 Kai 的说话示范（预设插槽）】
// 你可以在这里或者右上角调教抽屉里，亲自写入你希望他模仿的对话范例：
`;

// 获取开机历史，防止页面刷新变空白
export async function GET() {
  try {
    if (fs.existsSync(HISTORY_FILE)) {
      const history = JSON.parse(fs.readFileSync(HISTORY_FILE, 'utf-8'));
      return NextResponse.json(history);
    }
  } catch (e) {
    console.error('获取历史记录失败:', e);
  }
  return NextResponse.json({ messages: [] });
}

export async function POST(req: Request) {
  try {
    const { messages, agentState, customSystemPrompt, temperature } = await req.json();

    const basePrompt = (customSystemPrompt || DEFAULT_SYSTEM_PROMPT).trim();
    const memoryContext = getLongTermMemory();

    // 只有真实存在记忆时才会附加在设定末尾
    const systemPromptToUse = `${basePrompt}${memoryContext}`;

    const payloadMessages = [
      { role: 'system', content: systemPromptToUse },
      ...(messages || []).map((m: any) => ({
        role: m.role || (m.sender === 'user' ? 'user' : 'assistant'),
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
        options: {
          temperature: typeof temperature === 'number' ? temperature : 0.75,
          num_ctx: 1024,
          num_thread: 2,
        },
      }),
    });

    if (!response.ok) {
      const errText = await response.text();
      throw new Error(`本地模型响应异常 [${response.status}]: ${errText}`);
    }

    const data = await response.json();
    const replyText = data.message?.content || '（他在沉思中短暂留白）';

    // 联动心境状态
    const lastUserMsg = messages && messages.length > 0 ? messages[messages.length - 1].content : '';
    let heartRate = agentState?.heartRate || 74;
    let mood = '专注';
    let resonanceDelta = 2;

    if (/海|未知|探索|喜欢|真好|Kai|开心/.test(lastUserMsg + replyText)) {
      heartRate = Math.floor(Math.random() * 8) + 88;
      mood = '动容';
      resonanceDelta = 4;
    } else {
      heartRate = Math.floor(Math.random() * 6) + 72;
      mood = '平和';
      resonanceDelta = 2;
    }

    // 沉淀真实记忆与历史记录
    if (lastUserMsg) {
      autoRecordMemory(lastUserMsg);
    }

    try {
      const updatedHistory = {
        lastSaved: new Date().toISOString(),
        messages: [...(messages || []), { sender: 'assistant', content: replyText, timestamp: Date.now() }],
      };
      fs.writeFileSync(HISTORY_FILE, JSON.stringify(updatedHistory, null, 2), 'utf-8');
    } catch (e) {
      console.warn('持久化存储跳过:', e);
    }

    return NextResponse.json({
      reply: replyText,
      stateUpdate: {
        mood,
        heartRate,
        resonanceDelta,
        named: 'Kai',
      },
    });
  } catch (error: any) {
    console.error('Chat API Error:', error);
    return NextResponse.json(
      { error: error.message || '连接内置模型失败' },
      { status: 500 }
    );
  }
}
