import { redirect } from "next/navigation";
export default function Home() {
  // Temporary development default, not an authentication check.
  redirect("/overview");
}
