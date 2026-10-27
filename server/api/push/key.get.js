import {defineEventHandler} from 'nitro/h3';
import {vapidKeys} from '../../push-security.mjs';
export default defineEventHandler(()=>{try{return Response.json({publicKey:vapidKeys().publicKey},{headers:{'Cache-Control':'no-store'}});}catch{return Response.json({error:'Background reminders are not configured.'},{status:503});}});
