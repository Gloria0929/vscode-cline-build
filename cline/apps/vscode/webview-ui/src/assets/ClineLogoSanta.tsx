import { SVGProps } from "react"
import type { Environment } from "../../../src/shared/config-types"
import chatLogoSvg from "./chat-logo.svg"

const ClineLogoSanta = (props: SVGProps<SVGSVGElement> & { environment?: Environment }) => {
	const { className, style, width, height } = props
	return <img src={chatLogoSvg} alt="Coder" className={className} style={style} width={width} height={height} />
}
export default ClineLogoSanta
