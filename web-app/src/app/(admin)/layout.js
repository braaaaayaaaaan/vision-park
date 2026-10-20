import AdminShell from "@/components/admin-shell";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { ACCESS_COOKIE, verifyAdministrator } from "@/lib/auth.mjs";

export default async function AdminLayout({ children }) {
  // Verify again at the rendering boundary; never trust a client-supplied role.
  let reason;
  try {
    await verifyAdministrator((await cookies()).get(ACCESS_COOKIE)?.value);
  } catch (error) {
    reason = error.status === 403 ? "denied" : error.status === 401 ? "expired" : "unavailable";
  }
  if (reason) redirect(`/login?reason=${reason}`);
  return <AdminShell>{children}</AdminShell>;
}
