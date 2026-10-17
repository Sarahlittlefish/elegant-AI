// 用网页版自己的 loadKaiPersona() 生成系统提示词，给 Swift 版对照。
const { loadKaiPersona } = await import(process.argv[2] + '/frontend/src/lib/persona/loadPersona.ts');
process.stdout.write(loadKaiPersona());
