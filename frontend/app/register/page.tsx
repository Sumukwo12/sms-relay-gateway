import type { Metadata } from "next";
import AuthForm from "../components/auth-form";

export const metadata: Metadata = {
  title: "Create an account",
  description:
    "Create a free SMS Gateway account, link your Android phone and get API keys to send OTP codes and SMS from your website.",
  alternates: { canonical: "/register" },
};

export default function RegisterPage() {
  return <AuthForm mode="register" />;
}
