"use client";
import React, { useState, useEffect, useRef } from "react";
import Link from "next/link";
import {
  Send,
  Sparkles,
  Settings,
  Clock,
  Heart,
  ShieldAlert,
  Radio,
  Cat,
  Compass,
  Key,
  BookOpen,
  CheckCircle,
  HelpCircle,
  Info,
} from "lucide-react";
import { MemoryItem, MentalState } from "@/lib/types/kai";
import { getPragueEnvironment } from "@/lib/events/eventEngine";
interface ChatMessage {
  id: string;
  sender: "user" | "kai";
  content: string;
  timestamp: string;
  mentalState?: MentalState | null;
  recalledMemories?: MemoryItem[];
}
export default function ChatPage() {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [inputValue, setInputValue] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [apiKey, setApiKey] = useState("");
  const [resonanceRate, setResonanceRate] = useState(15.0);
  const [pragueEnv, setPragueEnv] = useState<any>(null);
  const [showInfoModal, setShowInfoModal] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  // 动态年龄计算（2006 年 5 月 27 日出生）
  const currentYear = new Date().getFullYear();
  const kaiAge = currentYear - 2006;
  useEffect(() => {
    const savedKey = localStorage.getItem("companion_api_key") || "";
    setApiKey(savedKey);
    const savedResonance = localStorage.getItem("kai_resonance_rate");
    if (savedResonance) {
      setResonanceRate(parseFloat(savedResonance));
    }
    // 初始化布拉格环境时钟
    setPragueEnv(getPragueEnvironment());
    const interval = setInterval(() => {
      setPragueEnv(getPragueEnvironment());
    }, 60000);
    // 初始欢迎消息：复现破冰的单个问号 "?"
    const savedHistory = localStorage.getItem("kai_chat_history");
    if (savedHistory) {
      try {
        setMessages(JSON.parse(savedHistory));
      } catch (e) {
        initDefaultIcebreaker();
      }
    } else {
      initDefaultIcebreaker();
    }
    return () => clearInterval(interval);
  }, []);
  const initDefaultIcebreaker = () => {
    const initialMsgs: ChatMessage[] = [
      {
        id: "msg_icebreaker_0",
        sender: "user",
        content: "(3.6-4.3)发饰跟随曲线头发v1.0 提取码: qsmv",
        timestamp: "2025-03-14 18:12",
      },
      {
        id: "msg_icebreaker_1",
        sender: "user",
        content: "¡™£¢∞§¶•ªº–≠«‘“πøˆ¨¥†®´∑œåßƒ©˙∆˚¬…æ÷≥≤µ˜∫√ç√",
        timestamp: "2025-03-14 18:13",
      },
      {
        id: "msg_icebreaker_2",
        sender: "kai",
        content: "?",
        timestamp: "Just now",
      },
    ];
    setMessages(initialMsgs);
  };
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);
  const handleSendMessage = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!inputValue.trim() || isLoading) return;
    const userText = inputValue.trim();
    setInputValue("");
    const newMsg: ChatMessage = {
      id: `msg_u_${Date.now()}`,
      sender: "user",
      content: userText,
      timestamp: new Date().toLocaleTimeString([], {
        hour: "2-digit",
        minute: "2-digit",
      }),
    };
    const updatedMessages = [...messages, newMsg];
    setMessages(updatedMessages);
    setIsLoading(true);
    try {
      const response = await fetch("/api/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          messages: updatedMessages.map((m) => ({
            sender: m.sender,
            content: m.content,
          })),
          agentState: {
            resonanceRate,
          },
          clientApiKey: apiKey,
        }),
      });
      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.error || "请求失败");
      }
      const data = await response.json();
      const kaiMsg: ChatMessage = {
        id: `msg_k_${Date.now()}`,
        sender: "kai",
        content: data.reply,
        timestamp: new Date().toLocaleTimeString([], {
          hour: "2-digit",
          minute: "2-digit",
        }),
        mentalState: data.mentalState,
        recalledMemories: data.recalledMemories,
      };
      const finalMessages = [...updatedMessages, kaiMsg];
      setMessages(finalMessages);
      localStorage.setItem("kai_chat_history", JSON.stringify(finalMessages));
      if (data.stateUpdate?.resonanceRate !== undefined) {
        setResonanceRate(data.stateUpdate.resonanceRate);
        localStorage.setItem(
          "kai_resonance_rate",
          data.stateUpdate.resonanceRate.toString(),
        );
      }
    } catch (err: any) {
      const errorMsg: ChatMessage = {
        id: `msg_err_${Date.now()}`,
        sender: "kai",
        content: `[网络或 API 异常: ${err.message || "请检查右上角智谱 API Key 配置"}]`,
        timestamp: new Date().toLocaleTimeString([], {
          hour: "2-digit",
          minute: "2-digit",
        }),
      };
      setMessages((prev) => [...prev, errorMsg]);
    } finally {
      setIsLoading(false);
    }
  };
  // 获取关系羁绊阶段文本
  const getRelationshipStage = (rate: number) => {
    if (rate <= 20)
      return {
        label: "破冰试探与戒备",
        color: "text-neutral-500",
        bg: "bg-neutral-100",
      };
    if (rate <= 50)
      return {
        label: "恶趣味互怼 (ENTP)",
        color: "text-amber-600",
        bg: "bg-amber-50",
      };
    if (rate <= 80)
      return {
        label: "精神共振与私密切片",
        color: "text-blue-600",
        bg: "bg-blue-50",
      };
    return {
      label: "隐性护短与理性兜底",
      color: "text-emerald-600",
      bg: "bg-emerald-50",
    };
  };
  const currentStage = getRelationshipStage(resonanceRate);
  return (
    <div className="flex flex-col h-screen bg-neutral-50 text-neutral-900 font-sans">
      {/* 顶部导航栏 */}
      <header className="flex items-center justify-between px-4 py-3 bg-white border-b border-neutral-200 shadow-sm z-10">
        <div className="flex items-center gap-3">
          <div className="relative">
            <div className="w-10 h-10 rounded-full bg-neutral-900 text-white flex items-center justify-center font-bold text-sm shadow-inner">
              @/
            </div>
            <span className="absolute bottom-0 right-0 w-3 h-3 bg-emerald-500 border-2 border-white rounded-full"></span>
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-base font-semibold text-neutral-900">
                Kai Novák
              </h1>
              <span className="text-xs text-neutral-500 font-mono">(@/)</span>
              <span className="text-[11px] bg-neutral-100 text-neutral-600 px-2 py-0.5 rounded-full font-medium">
                {kaiAge}岁 · 查理大学 MFF
              </span>
            </div>
            <p className="text-xs text-neutral-500 flex items-center gap-1.5 truncate max-w-[280px] sm:max-w-md">
              <span className="inline-block w-1.5 h-1.5 rounded-full bg-neutral-400"></span>
              {pragueEnv?.currentActivity || "布拉格查理大学计算语言学在读"}
            </p>
          </div>
        </div>
        {/* 状态指示与快捷入口 */}
        <div className="flex items-center gap-2 sm:gap-4">
          <div className="hidden sm:flex items-center gap-1.5 text-xs text-neutral-500 bg-neutral-50 px-2.5 py-1.5 rounded-lg border border-neutral-200">
            <Clock className="w-3.5 h-3.5 text-neutral-400" />
            <span>布拉格 {pragueEnv?.localTimeString || "14:30"}</span>
          </div>
          <div
            className={`hidden md:flex items-center gap-1.5 text-xs px-2.5 py-1.5 rounded-lg border border-neutral-200 ${currentStage.bg}`}
          >
            <Heart className={`w-3.5 h-3.5 ${currentStage.color}`} />
            <span className={`font-medium ${currentStage.color}`}>
              {currentStage.label} ({resonanceRate.toFixed(1)}%)
            </span>
          </div>
          <button
            onClick={() => setShowInfoModal(true)}
            className="p-2 text-neutral-500 hover:text-neutral-900 hover:bg-neutral-100 rounded-lg transition"
            title="查看 Kai 的真实身份档案"
          >
            <Info className="w-4 h-4" />
          </button>
          <Link
            href="/tuning"
            className="flex items-center gap-1 text-xs bg-neutral-900 text-white px-3 py-1.5 rounded-lg hover:bg-neutral-800 transition font-medium shadow-sm"
          >
            <Settings className="w-3.5 h-3.5" />
            <span>调谐实验室</span>
          </Link>
        </div>
      </header>
      {/* 消息滚动区 */}
      <main className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-4 max-w-3xl w-full mx-auto">
        <div className="text-center my-2">
          <span className="text-[11px] bg-neutral-200/60 text-neutral-500 px-3 py-1 rounded-full">
            iMessage 会话已开启 · 经由 @/ 账号端到端加密
          </span>
        </div>
        {messages.map((msg) => {
          const isUser = msg.sender === "user";
          return (
            <div
              key={msg.id}
              className={`flex flex-col ${isUser ? "items-end" : "items-start"} space-y-1 animate-fade-in`}
            >
              <div
                className={`max-w-[85%] sm:max-w-[75%] px-4 py-2.5 rounded-2xl text-sm leading-relaxed shadow-sm ${
                  isUser
                    ? "bg-blue-600 text-white rounded-br-sm"
                    : "bg-white text-neutral-900 border border-neutral-200/80 rounded-bl-sm"
                }`}
              >
                <p className="whitespace-pre-wrap select-text">{msg.content}</p>
              </div>
              {/* Kai 回复附带的心理状态小贴纸 */}
              {!isUser && msg.mentalState && (
                <div className="flex items-center gap-2 text-[10px] text-neutral-400 pl-1">
                  <span className="font-mono">
                    心智:{" "}
                    {msg.mentalState.delta_affection >= 0
                      ? `+${msg.mentalState.delta_affection}`
                      : msg.mentalState.delta_affection}
                    分
                  </span>
                  <span>·</span>
                  <span>{msg.mentalState.reason}</span>
                </div>
              )}
              <span className="text-[10px] text-neutral-400 px-1 font-mono">
                {msg.timestamp}
              </span>
            </div>
          );
        })}
        {isLoading && (
          <div className="flex items-center gap-2 text-neutral-400 text-xs italic pl-2">
            <span className="w-2 h-2 rounded-full bg-neutral-400 animate-pulse"></span>
            Kai 正在输入...
          </div>
        )}
        <div ref={messagesEndRef} />
      </main>
      {/* 底部输入框 */}
      <footer className="p-3 sm:p-4 bg-white border-t border-neutral-200">
        <form
          onSubmit={handleSendMessage}
          className="max-w-3xl mx-auto flex items-center gap-2"
        >
          <input
            type="text"
            value={inputValue}
            onChange={(e) => setInputValue(e.target.value)}
            placeholder="发消息给 Kai (@/)..."
            disabled={isLoading}
            className="flex-1 px-4 py-2.5 text-sm bg-neutral-100 border border-transparent rounded-xl focus:bg-white focus:border-blue-500 focus:outline-none transition"
          />
          <button
            type="submit"
            disabled={isLoading || !inputValue.trim()}
            className="p-2.5 bg-blue-600 text-white rounded-xl hover:bg-blue-700 disabled:opacity-40 transition shadow-sm"
          >
            <Send className="w-4 h-4" />
          </button>
        </form>
      </footer>
      {/* 身份全景资料弹窗 */}
      {showInfoModal && (
        <div className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl max-w-lg w-full p-6 shadow-xl border border-neutral-200 space-y-4 max-h-[85vh] overflow-y-auto">
            <div className="flex justify-between items-start">
              <div>
                <h3 className="text-lg font-bold text-neutral-900">
                  Kai Novák (凯·诺瓦克)
                </h3>
                <p className="text-xs text-neutral-500 font-mono">
                  布拉格查理大学 · 计算语言学专业 (MFF)
                </p>
              </div>
              <button
                onClick={() => setShowInfoModal(false)}
                className="text-neutral-400 hover:text-neutral-600 text-sm font-bold p-1"
              >
                ✕
              </button>
            </div>
            <div className="space-y-3 text-xs text-neutral-600 leading-relaxed border-t border-neutral-100 pt-3">
              <p>
                <strong>真实身份：</strong>Kai 是一名真实的 20
                岁捷克大学生（出生于 2006 年 5 月 27
                日），就读于享誉世界的布拉格查理大学数理学院。绝非任何试图伪装人类的虚拟
                AI 助手。
              </p>
              <p>
                <strong>性格特质：</strong>典型
                ENTP（辩论家）。思维极度锐利，对形式逻辑与认知模型充满探求欲，极度厌恶官腔、套话与讨好型客套，自带中欧干燥冷幽默。
              </p>
              <p>
                <strong>身世与羁绊：</strong>
                家乡位于比尔森工业城，父母为布拉格波希米亚自由派文艺工作者。随身携带比尔森拉德布扎河边的光滑鹅卵石；桌上放着犹太区修表匠舅爷爷遗留的旧短波收音机；宿舍收留了在车站捡到的流浪猫
                Syntax。
              </p>
              <p>
                <strong>@/ 账号渊源：</strong>你多年来把未注册的保留字 @/
                当成私密废纸篓与剪贴板堆放日常杂物。账号释放被 Kai
                注册后，他被乱码符号与发饰曲线插件轰炸，以一个极其克制的英文问号「?」破冰。
              </p>
            </div>
            <div className="pt-2 flex justify-end">
              <button
                onClick={() => setShowInfoModal(false)}
                className="px-4 py-2 bg-neutral-900 text-white text-xs font-medium rounded-xl hover:bg-neutral-800 transition"
              >
                知道了
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
