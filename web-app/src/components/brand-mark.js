import Image from 'next/image';

export default function BrandMark({ inverse = false, className }) {
  return <Image className={className} src={`/branding/visionpark-falcon-${inverse ? 'white' : 'blue'}.svg`} alt="" aria-hidden="true" width={52} height={35} preload />;
}
