import {defineEventHandler} from 'nitro/h3';
import handler from '../ai-handler.mjs';
export default defineEventHandler(async ({req})=>{
 const headers={};let status=200,result;
 const res={setHeader:(k,v)=>headers[k]=v,status(n){status=n;return this},json(v){result=v;return v}};
 let body;try{const raw=await req.text();if(raw.length>3700000)return Response.json({error:'Image too large.'},{status:413});body=raw;}catch{return Response.json({error:'Could not read request.'},{status:400});}
 await handler({method:'POST',headers:Object.fromEntries(req.headers),body},res);
 return Response.json(result,{status,headers});
});
