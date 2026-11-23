import type { Metadata } from "next";
import AuthForm from "../components/auth-form";

export const metadata: Metadata = {
  title: "Sign in",
  description: "Sign in to your SMS Gateway account to manage your phones, API keys and messages.",
  alternates: { canonical: "/login" },
};

export default function LoginPage() {
  return <AuthForm mode="login" />;
}
