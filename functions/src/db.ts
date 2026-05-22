import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

admin.initializeApp();
export const db = admin.firestore();
export { FieldValue };
