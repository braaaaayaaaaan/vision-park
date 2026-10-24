import "./globals.css";
export const metadata = {
  title: { default: "VisionPark Admin", template: "%s | VisionPark Admin" },
  description: "VisionPark parking administration.",
};
export default function RootLayout({ children }) {
  return <html lang="en-MY"><body>{children}</body></html>;
}
