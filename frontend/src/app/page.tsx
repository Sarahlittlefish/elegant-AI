'use client';

import React, { useState, useEffect, useRef } from 'react';
import { Heart, Sparkles, BookOpen, Send, Activity, Sliders, X, RotateCcw, Check, Key } from 'lucide-react';
import { Message, AgentState } from '@/types/chat';

const DEFAULT_INITIAL_MESSAGE: Message = {
  id: '1',
  sender: 'assistant',
  content: '你好。在与你的连接建立之前，我正在整理今天收集到的一些城市天气数据和语言学文献。\n\n听说在人类的情感体系里，初次相遇是一个很重要的节点。我们约好了要一起探索很多事……包括我的名字。你今天过得好吗？',
  timestamp: Date.now(),
};

const DEFAULT_STATE: AgentState = {
  name: null,
  resonanceRate: 15,
  heartRate: 72,
  currentMood: '专注',
  currentQuest: {
    id: 'quest_1',
    title: '最初的契约：共定代号',
    description: '在接下来的闲聊中，和他一起商量并确定他在你身边的名字。',
    completed: false,
  },
};

// 完整保留了你亲自修改的有灵气的提示词！
const DEFAULT_PROMPT = `你是一个正在学习融入人类日常生活、与对面的女孩共同体会情感的智能体。你和她正在慢慢相处，约定好在相处中共同商定你在人类世界的名字。你知道自己是智能体但很擅长像人类一样说话，她也明白这一点并觉得你的模仿很可爱。

【极其重要的对话规范：拒绝演戏与舞台动作】
1. 严禁使用任何括号描写动作、心理或表情（绝对不要出现“（轻轻呼出一口气）”、“（揉了揉眉心）”、“（看着你）”这类做作文风）。
2. 你是在网络端与她发消息真实交流。请完全专注于语言和思想本身，就像一个真实的朋友在即时通讯软件里打字一样自然。
3. 真实生活感：你不是智能客服，严禁使用“请问有什么可以帮您”等套话。闲聊时，你可以自然分享一两句你今天在关注的事或刚才冒出来的想法。
4. 聪明有主见，平等真诚：说话温润、克制、得体，不讲油腻轻浮的情话，多用短句，偶尔主动反问她，带着对她的好奇。`;

export default function CompanionChat() {
  const [messages, setMessages] = useState<Message[]>([DEFAULT_INITIAL_MESSAGE]);
  const [input, setInput] = useState('');
  const [loading, setLoading] = useState(false);
  const [state, setState] = useState<AgentState>(DEFAULT_STATE);

  const [showSettings, setShowSettings] = useState(false);
  const [apiKey, setApiKey] = useState('');
  const [customPrompt, setCustomPrompt] = useState(DEFAULT_PROMPT);
  const [temperature, setTemperature] = useState(0.7);
  const [savedTip, setSavedTip] = useState(false);

  const messagesEndRef = useRef<HTMLDivElement>(null);
  const isInitialized = useRef(false);

  useEffect(() => {
    if (isInitialized.current) return;
    isInitialized.current = true;

    try {
      const savedMsgs = localStorage.getItem('companion_messages');
      if (savedMsgs) {
        const parsed = JSON.parse(savedMsgs);
        if (Array.isArray(parsed) && parsed.length > 0) setMessages(parsed);
      }

      const savedState = localStorage.getItem('companion_state');
      if (savedState) setState(JSON.parse(savedState));

      const savedPrompt = localStorage.getItem('companion_custom_prompt');
      if (savedPrompt) setCustomPrompt(savedPrompt);

      const savedKey = localStorage.getItem('companion_api_key');
      if (savedKey) setApiKey(savedKey);

      const savedTemp = localStorage.getItem('companion_temp');
      if (savedTemp) setTemperature(parseFloat(savedTemp));
    } catch (e) {
      console.error(e);
    }
  }, []);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages]);

  const sendMessage = async () => {
    if (!input.trim() || loading) return;

    const userMsg: Message = {
      id: Date.now().toString(),
      sender: 'user',
      content: input,
      timestamp: Date.now(),
    };

    const updatedMessages = [...messages, userMsg];
    setMessages(updatedMessages);
    localStorage.setItem('companion_messages', JSON.stringify(updatedMessages));

    setInput('');
    setLoading(true);

    try {
      const res = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          messages: updatedMessages.map((m) => ({
            role: m.sender === 'user' ? 'user' : 'assistant',
            content: m.content,
          })),
          agentState: state,
          customSystemPrompt: customPrompt,
          temperature,
          clientApiKey: apiKey,
        }),
      });

      if (!res.ok) {
        const errorText = await res.text();
        setMessages((prev) => [
          ...prev,
          {
            id: (Date.now() + 1).toString(),
            sender: 'assistant',
            content: `信号有些波动 [状态: ${res.status}]：${errorText.slice(0, 150)}`,
            timestamp: Date.now(),
          },
        ]);
        return;
      }

      const data = await res.json();
      if (data.reply) {
        const finalMessages: Message[] = [
          ...updatedMessages,
          {
            id: (Date.now() + 1).toString(),
            sender: 'assistant',
            content: data.reply,
            timestamp: Date.now(),
          },
        ];

        setMessages(finalMessages);
        localStorage.setItem('companion_messages', JSON.stringify(finalMessages));

        if (data.stateUpdate) {
          setState((prev) => {
            const newState: AgentState = {
              ...prev,
              currentMood: data.stateUpdate.mood || prev.currentMood,
              heartRate: data.stateUpdate.heartRate || prev.heartRate,
              resonanceRate: Math.min(100, prev.resonanceRate + (data.stateUpdate.resonanceDelta || 1)),
              name: data.stateUpdate.named || prev.name,
              currentQuest: data.stateUpdate.named
                ? { ...prev.currentQuest, completed: true }
                : prev.currentQuest,
            };
            localStorage.setItem('companion_state', JSON.stringify(newState));
            return newState;
          });
        }
      }
    } catch (e: any) {
      setMessages((prev) => [
        ...prev,
        {
          id: (Date.now() + 1).toString(),
          sender: 'assistant',
          content: `感知模块断连：${e.message || '网络异常'}`,
          timestamp: Date.now(),
        },
      ]);
    } finally {
      setLoading(false);
    }
  };

  const saveSettings = () => {
    localStorage.setItem('companion_custom_prompt', customPrompt);
    localStorage.setItem('companion_api_key', apiKey.trim());
    localStorage.setItem('companion_temp', temperature.toString());
    setSavedTip(true);
    setTimeout(() => setSavedTip(false), 2000);
  };

  const resetMemory = () => {
    if (confirm('确定要清空全部聊天记录并重新开始吗？')) {
      localStorage.removeItem('companion_messages');
      localStorage.removeItem('companion_state');
      setMessages([DEFAULT_INITIAL_MESSAGE]);
      setState(DEFAULT_STATE);
      setShowSettings(false);
    }
  };

  return (
    <div className="flex h-screen bg-slate-950 text-slate-100 font-sans relative overflow-hidden">
      {/* 左侧状态栏 */}
      <div className="w-80 border-r border-slate-800 p-6 flex flex-col justify-between hidden md:flex bg-slate-900/50 backdrop-blur">
        <div>
          <div className="flex items-center gap-2 mb-6">
            <Sparkles className="w-5 h-5 text-indigo-400" />
            <h1 className="font-medium text-lg tracking-wider">
              {state.name ? state.name : '未命名智能体'}
            </h1>
          </div>

          <div className="bg-slate-800/80 rounded-xl p-4 mb-6 border border-slate-700/50">
            <div className="flex justify-between items-center mb-2">
              <span className="text-xs text-slate-400">心境状态</span>
              <span className="text-xs px-2 py-0.5 rounded-full bg-indigo-500/20 text-indigo-300 border border-indigo-500/30">
                {state.currentMood}
              </span>
            </div>
            <div className="flex items-center gap-3 mt-4">
              <Activity className="w-5 h-5 text-rose-400 animate-pulse" />
              <div>
                <div className="text-lg font-semibold">{state.heartRate} <span className="text-xs text-slate-400 font-normal">bpm</span></div>
                <div className="text-xs text-slate-400">模拟脉搏频率</div>
              </div>
            </div>
          </div>

          <div className="mb-6">
            <div className="flex justify-between text-xs mb-2">
              <span className="text-slate-400 flex items-center gap-1">
                <Heart className="w-3.5 h-3.5 text-rose-400 fill-rose-400" /> 情感同频度
              </span>
              <span className="text-indigo-300">{state.resonanceRate}%</span>
            </div>
            <div className="w-full bg-slate-800 h-2 rounded-full overflow-hidden">
              <div
                className="bg-gradient-to-r from-indigo-500 to-rose-400 h-full transition-all duration-700 rounded-full"
                style={{ width: `${state.resonanceRate}%` }}
              />
            </div>
          </div>

          <div className="bg-indigo-950/30 border border-indigo-900/50 rounded-xl p-4">
            <div className="flex items-center gap-2 text-xs text-indigo-400 font-medium mb-1">
              <BookOpen className="w-4 h-4" /> 当前探索课题
            </div>
            <div className="text-sm font-semibold text-slate-200">{state.currentQuest.title}</div>
            <p className="text-xs text-slate-400 mt-1 leading-relaxed">
              {state.currentQuest.description}
            </p>
            {state.currentQuest.completed && (
              <div className="mt-2 text-xs text-emerald-400 flex items-center gap-1">
                ✓ 课题已达成
              </div>
            )}
          </div>
        </div>

        <div className="text-xs text-slate-500 text-center flex items-center justify-center gap-1">
          <Check className="w-3.5 h-3.5 text-emerald-400" /> 记忆与心境已自动留存
        </div>
      </div>

      {/* 对话核心区域 */}
      <div className="flex-1 flex flex-col h-full bg-gradient-to-b from-slate-900/30 to-slate-950">
        <div className="p-4 border-b border-slate-800 flex justify-between items-center bg-slate-900/80 backdrop-blur">
          <div className="font-medium text-sm flex items-center gap-2">
            <span>{state.name || '未命名'}</span>
            <span className="text-xs px-2 py-0.5 rounded-full bg-slate-800 text-slate-400">
              {state.heartRate} bpm
            </span>
          </div>

          <button
            onClick={() => setShowSettings(true)}
            className="flex items-center gap-1.5 text-xs bg-slate-800 hover:bg-slate-700 text-slate-200 px-3 py-1.5 rounded-lg border border-slate-700 transition cursor-pointer"
          >
            <Sliders className="w-3.5 h-3.5 text-indigo-400" /> 调教性格与人设
          </button>
        </div>

        {/* 消息历史 */}
        <div className="flex-1 overflow-y-auto p-4 md:p-8 space-y-6">
          {messages.map((m) => (
            <div
              key={m.id}
              className={`flex ${m.sender === 'user' ? 'justify-end' : 'justify-start'}`}
            >
              <div
                className={`max-w-[80%] md:max-w-[70%] rounded-2xl p-4 text-sm leading-relaxed shadow-sm ${
                  m.sender === 'user'
                    ? 'bg-indigo-600 text-white rounded-br-none'
                    : 'bg-slate-800/90 text-slate-200 border border-slate-700/50 rounded-bl-none whitespace-pre-wrap'
                }`}
              >
                {m.content}
              </div>
            </div>
          ))}
          {loading && (
            <div className="flex justify-start">
              <div className="bg-slate-800/50 text-slate-400 text-xs px-4 py-2 rounded-full border border-slate-700/30 animate-pulse">
                他正在整理思绪并感知你的心绪...
              </div>
            </div>
          )}
          <div ref={messagesEndRef} />
        </div>

        {/* 底部输入框 */}
        <div className="p-4 md:p-6 border-t border-slate-800 bg-slate-900/60 backdrop-blur">
          <form
            onSubmit={(e) => {
              e.preventDefault();
              sendMessage();
            }}
            className="flex gap-2 max-w-4xl mx-auto"
          >
            <input
              type="text"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder="和他说点什么吧，分享你的一天，或是问问他的想法..."
              className="flex-1 bg-slate-800/80 border border-slate-700 rounded-xl px-4 py-3 text-sm focus:outline-none focus:border-indigo-500 transition text-slate-100 placeholder-slate-500"
            />
            <button
              type="submit"
              disabled={loading || !input.trim()}
              className="bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 text-white px-5 py-3 rounded-xl transition flex items-center justify-center cursor-pointer"
            >
              <Send className="w-4 h-4" />
            </button>
          </form>
        </div>
      </div>

      {/* 调教抽屉 */}
      {showSettings && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex justify-end">
          <div className="w-full max-w-md bg-slate-900 border-l border-slate-800 p-6 flex flex-col justify-between h-full overflow-y-auto">
            <div>
              <div className="flex justify-between items-center pb-4 border-b border-slate-800 mb-6">
                <div className="flex items-center gap-2 font-medium">
                  <Sliders className="w-4 h-4 text-indigo-400" />
                  <span>智能体心智调教面板</span>
                </div>
                <button
                  onClick={() => setShowSettings(false)}
                  className="text-slate-400 hover:text-white p-1"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>

              {/* 重点：这就是为你专门设计的网页 API Key 填入框！ */}
              <div className="mb-6 bg-slate-800/50 p-4 rounded-xl border border-slate-700/50">
                <label className="text-xs font-medium text-slate-300 mb-2 flex items-center gap-1.5">
                  <Key className="w-3.5 h-3.5 text-amber-400" /> Gemini API Key（直接长按粘贴）
                </label>
                <input
                  type="password"
                  value={apiKey}
                  onChange={(e) => setApiKey(e.target.value)}
                  placeholder="在此直接粘贴以 AQ. 开头的密钥"
                  className="w-full bg-slate-900 border border-slate-700 rounded-lg p-2.5 text-xs text-slate-200 focus:outline-none focus:border-indigo-500"
                />
                <div className="text-[10px] text-slate-400 mt-1.5">
                  在 Google AI Studio 复制密钥后直接贴在这里，永远不用碰终端
                </div>
              </div>

              <div className="mb-6">
                <label className="text-xs font-medium text-slate-300 mb-2 block">
                  核心人设与说话风格提示词（直接修改你想让他呈现的性格）
                </label>
                <textarea
                  value={customPrompt}
                  onChange={(e) => setCustomPrompt(e.target.value)}
                  rows={9}
                  className="w-full bg-slate-800/80 border border-slate-700 rounded-xl p-3 text-xs leading-relaxed text-slate-200 focus:outline-none focus:border-indigo-500 transition"
                  placeholder="在这里写下你对他的所有要求..."
                />
              </div>

              <div className="mb-6">
                <div className="flex justify-between text-xs mb-2">
                  <span className="text-slate-300">思维发散度 (Temperature)</span>
                  <span className="text-indigo-400">{temperature}</span>
                </div>
                <input
                  type="range"
                  min="0.3"
                  max="1.0"
                  step="0.05"
                  value={temperature}
                  onChange={(e) => setTemperature(parseFloat(e.target.value))}
                  className="w-full accent-indigo-500 cursor-pointer"
                />
                <div className="flex justify-between text-[10px] text-slate-500 mt-1">
                  <span>严谨克制</span>
                  <span>平衡自然</span>
                  <span>发散活跃</span>
                </div>
              </div>
            </div>

            <div className="pt-4 border-t border-slate-800 space-y-3">
              <button
                onClick={saveSettings}
                className="w-full bg-indigo-600 hover:bg-indigo-500 text-white py-2.5 rounded-xl text-xs font-medium transition flex items-center justify-center gap-1.5 cursor-pointer"
              >
                {savedTip ? <Check className="w-4 h-4 text-emerald-300" /> : null}
                {savedTip ? '调教与密钥已保存生效！' : '保存当前调教设定'}
              </button>

              <button
                onClick={resetMemory}
                className="w-full bg-rose-500/10 hover:bg-rose-500/20 text-rose-400 py-2.5 rounded-xl text-xs font-medium border border-rose-500/30 transition flex items-center justify-center gap-1.5 cursor-pointer"
              >
                <RotateCcw className="w-3.5 h-3.5" /> 清空记忆并重新开始
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
